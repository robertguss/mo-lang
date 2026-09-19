"""Scripted loopback double of the accepted mo-workspace-http-v1 frontend, for local controls.

It enforces the contract's request framing (POST /tool, the exact header set, Host, private
token, JSON media type, canonical Content-Length) and validates the body with the accepted
protocol.request, imported read-only. It never executes anything: each admitted call is answered
from a per-test script. Recorded requests keep sizes, hashes and parsed fields, never the token."""
import hashlib
import hmac
import json
from pathlib import Path
import re
import secrets
import socket
import sys
import threading
import time
import uuid

ROOT = Path(__file__).resolve().parents[5]
sys.path.insert(0, str(ROOT / 'toolchain/harness/executor'))
from workspace_http import protocol  # noqa: E402

ALLOWED = {'host', 'content-type', 'content-length', 'x-mo-workspace-token', 'connection'}


def envelope(req, **fields):
    value = dict(version=protocol.VERSION, run_id=req['run_id'], workspace_id=req['workspace_id'],
                 call_id=req['call_id'], accepted=True, state='success', execution='completed',
                 error=None, result=None)
    value.update(fields)
    return value


def success(req):
    """What the accepted projection returns for a successful call of each operation."""
    op = req['operation']
    if op == 'command':
        result = dict(exit_code=0, signal=None, execution_valid=True, stdout='ok\n', stderr='',
                      encoding='utf-8', truncated=False, elapsed_ms=12)
    else:
        result = {'list_files': {'items': [{'path': 'a.txt', 'length': 3, 'sha256': '0' * 64, 'mode': 420}]},
                  'search': {'items': [{'path': 'a.txt', 'offset': 2}]},
                  'read_file': {'text': 'remote text\n'}, 'write_file': {'written': True},
                  'exact_edit': {'edited': True}}[op]
        result = dict(result, truncated=False)
    return 200, envelope(req, result=result)


class Bridge:
    """script(req, n) -> (status, body) where body is a dict, bytes, or None to close silently.
    A float 'delay' may be returned as a third element to hold the response."""

    def __init__(self, script=None, run_id='r_1', observe=None):
        self.script = script or (lambda req, n: success(req))
        self.observe = observe or (lambda: None)
        self.run_id = run_id
        self.workspace_id = uuid.uuid4().hex
        self.token = secrets.token_hex(32)
        self.requests = []
        self.errors = []
        self.listener = socket.socket()
        self.listener.bind(('127.0.0.1', 0))
        self.listener.listen(8)
        self.listener.settimeout(.1)
        self.port = self.listener.getsockname()[1]
        self.closed = False
        self.thread = threading.Thread(target=self._accept, daemon=True)
        self.thread.start()

    def config(self, **override):
        value = dict(version=protocol.VERSION, port=self.port, run_id=self.run_id,
                     workspace_id=self.workspace_id, token=self.token)
        value.update(override)
        return value

    def write_config(self, path, **override):
        path = Path(path)
        path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        path.parent.chmod(0o700)
        path.write_text(json.dumps(self.config(**override)))
        path.chmod(0o600)
        return path

    def close(self):
        self.closed = True
        self.thread.join(5)
        self.listener.close()

    def _accept(self):
        while not self.closed:
            try:
                conn, _ = self.listener.accept()
            except socket.timeout:
                continue
            except OSError:
                break
            threading.Thread(target=self._serve, args=(conn,), daemon=True).start()

    def _read(self, conn):
        conn.settimeout(30)
        data = bytearray()
        while b'\r\n\r\n' not in data:
            part = conn.recv(65536)
            if not part:
                raise EOFError('headers')
            data.extend(part)
        head, _, rest = bytes(data).partition(b'\r\n\r\n')
        lines = head.decode('ascii').split('\r\n')
        headers = {}
        for line in lines[1:]:
            key, _, value = line.partition(':')
            key = key.lower()
            if key not in ALLOWED or key in headers:
                raise ValueError('header ' + key)
            headers[key] = value.strip(' ')
        length = headers.get('content-length', '')
        if not re.fullmatch(r'[1-9][0-9]{0,8}', length):
            raise ValueError('content-length')
        body = bytearray(rest)
        while len(body) < int(length):
            part = conn.recv(65536)
            if not part:
                raise EOFError('body')
            body.extend(part)
        return lines[0], headers, bytes(body)

    def _serve(self, conn):
        arrived = time.monotonic()
        row = dict(arrived=arrived, observed=self.observe())
        try:
            first, headers, raw = self._read(conn)
            row.update(first=first, host=headers.get('host'), content_type=headers.get('content-type'),
                       connection=headers.get('connection'), bytes=len(raw),
                       sha256=hashlib.sha256(raw).hexdigest(),
                       token_ok=hmac.compare_digest(headers.get('x-mo-workspace-token', ''), self.token),
                       header_names=sorted(headers))
            if first != 'POST /tool HTTP/1.1' or headers.get('host') != f'127.0.0.1:{self.port}':
                raise ValueError('request line or host')
            if not row['token_ok'] or headers.get('content-type') != 'application/json':
                raise ValueError('token or media type')
            req = protocol.request(raw, self.run_id, self.workspace_id)
            row.update(operation=req['operation'], call_id=req['call_id'],
                       args={k: (v if k == 'timeout_ms' or len(v) <= 256 else f'<{len(v)} chars>')
                             for k, v in req['args'].items()})
            self.requests.append(row)
            answer = self.script(req, len(self.requests))
            status, body = answer[0], answer[1]
            if len(answer) > 2:
                time.sleep(answer[2])
            if body is None:
                row['answered'] = False
                return
            raw_out = body if isinstance(body, bytes) else protocol.encode(body)
            try:
                conn.sendall(f'HTTP/1.1 {status} Result\r\nContent-Type: application/json\r\n'
                             f'Content-Length: {len(raw_out)}\r\nConnection: close\r\n\r\n'.encode('ascii') + raw_out)
                row['answered'] = status
            except OSError as exc:  # the client gave up first; not a request error
                row['answered'] = f'unsent: {type(exc).__name__}'
        except Exception as exc:  # an invalid request, recorded, never raised into the test thread
            row['error'] = f'{type(exc).__name__}: {exc}'
            self.errors.append(row)
        finally:
            try:
                conn.close()
            except OSError:
                pass


class Model:
    """Scripted model on loopback: POST /complete answered with the next reply in order. Each
    request is recorded with its arrival time, run header, transcript length and raw body."""

    def __init__(self, replies, delays=None, observe=None):
        self.replies = list(replies)
        self.delays = delays or {}
        self.observe = observe or (lambda: None)
        self.requests = []
        self.listener = socket.socket()
        self.listener.bind(('127.0.0.1', 0))
        self.listener.listen(8)
        self.listener.settimeout(.1)
        self.port = self.listener.getsockname()[1]
        self.closed = False
        self.thread = threading.Thread(target=self._accept, daemon=True)
        self.thread.start()

    def close(self):
        self.closed = True
        self.thread.join(5)
        self.listener.close()

    def _accept(self):
        while not self.closed:
            try:
                conn, _ = self.listener.accept()
            except socket.timeout:
                continue
            except OSError:
                break
            threading.Thread(target=self._serve, args=(conn,), daemon=True).start()

    def _serve(self, conn):
        row = dict(arrived=time.monotonic(), observed=self.observe())
        try:
            conn.settimeout(30)
            data = bytearray()
            while b'\r\n\r\n' not in data:
                part = conn.recv(65536)
                if not part:
                    raise EOFError('headers')
                data.extend(part)
            head, _, rest = bytes(data).partition(b'\r\n\r\n')
            lines = head.decode('latin-1').split('\r\n')
            headers = {k.lower(): v.strip() for k, _, v in (l.partition(':') for l in lines[1:])}
            body = bytearray(rest)
            while len(body) < int(headers.get('content-length', '0')):
                part = conn.recv(65536)
                if not part:
                    raise EOFError('body')
                body.extend(part)
            request = json.loads(bytes(body))
            row.update(first=lines[0], run=headers.get('x-run'), raw=bytes(head) + b'\r\n\r\n' + bytes(body),
                       transcript=len(request.get('transcript', [])), bytes=len(body))
            self.requests.append(row)
            n = len(self.requests)
            reply = self.replies[n - 1] if n <= len(self.replies) else dict(done='no more replies', tokens=0)
            time.sleep(self.delays.get(n, 0))
            raw = json.dumps(reply).encode()
            conn.sendall(b'HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: '
                         + str(len(raw)).encode() + b'\r\nConnection: close\r\n\r\n' + raw)
        except Exception as exc:
            row['error'] = f'{type(exc).__name__}: {exc}'
        finally:
            try:
                conn.close()
            except OSError:
                pass
