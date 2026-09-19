"""Private operator API and bounded loopback HTTP admission frontend."""
import base64
import hmac
import json
import os
from pathlib import Path
import re
import secrets
import select
import socket
import subprocess
import sys
import threading
import time
import uuid

from . import owner
from .protocol import ID, REQUEST_CAP, Refused, encode, envelope, request


class Bridge:
    def __init__(self, run_id, directory, source, *, selection, verifier):
        # Validate all trusted inputs before creating output or starting anything.
        from remote import selection as validate_selection
        from adapter import validate_checks
        from workspace_files import validate_import
        if type(run_id) is not str or not ID.fullmatch(run_id):
            raise ValueError('run identity')
        if type(selection) is not dict or set(selection) != {'policy', 'image', 'toolchain'}:
            raise ValueError('selection')
        validate_selection(**selection)
        if type(verifier) is not dict or set(verifier) != {'script', 'checks', 'seconds'}:
            raise ValueError('verifier')
        validate_checks(verifier['checks'])
        if type(verifier['script']) is not str or type(verifier['seconds']) not in (int, float) or not .5 <= verifier['seconds'] <= 120:
            raise ValueError('verifier')
        validate_import(list(source.items()))
        self.run_id, self.workspace_id = run_id, uuid.uuid4().hex
        self.directory = Path(directory).absolute()
        self.directory.mkdir(mode=0o700, parents=True, exist_ok=False)
        self.directory = self.directory.resolve()
        os.chmod(self.directory, 0o700)
        self.token = secrets.token_hex(32)
        self.config = dict(run_id=run_id, workspace_id=self.workspace_id, directory=str(self.directory),
                           source={key: base64.b64encode(value).decode('ascii') for key, value in source.items()},
                           selection=selection, verifier=verifier)
        owner.private_write(self.directory / 'config.json', self.config)
        owner.private_write(self.directory / 'capability.json', {'token': self.token})
        self.lock = threading.Lock()
        self.state_lock = threading.Lock()
        self.closed = True
        self.calls = set()
        self.process = self.ipc = self.listener = None
        self.threads = set()
        self.connections = set()
        self.slots = threading.BoundedSemaphore(4)
        self.deadline = 0

    def start(self):
        if self.process is not None:
            raise RuntimeError('one start only')
        parent, child = socket.socketpair()
        env = dict(os.environ, PYTHONDONTWRITEBYTECODE='1')
        env['PYTHONPATH'] = str(Path(__file__).resolve().parents[1])
        log = (self.directory / 'owner.log').open('xb')
        os.chmod(self.directory / 'owner.log', 0o600)
        try:
            self.process = subprocess.Popen([sys.executable, '-B', '-m', 'workspace_http.owner',
                                             str(child.fileno()), str(self.directory / 'config.json')],
                                            pass_fds=(child.fileno(),), env=env, stdout=log, stderr=log)
        finally:
            child.close()
            log.close()
        self.ipc = parent
        try:
            parent.settimeout(40)
            ready = owner.receive(parent)
            if ready.get('ready') is not True:
                raise RuntimeError('startup failed')
            self.deadline = ready['deadline']
            self.listener = socket.socket()
            self.listener.bind(('127.0.0.1', 0))
            self.listener.listen(4)
            self.listener.settimeout(.1)
            self.port = self.listener.getsockname()[1]
            self.closed = False
            owner.private_write(self.directory / 'ready.json', dict(port=self.port, run_id=self.run_id,
                                workspace_id=self.workspace_id, owner_pid=self.process.pid))
            self.accept_thread = threading.Thread(target=self._accept, daemon=True)
            self.accept_thread.start()
            return self
        except BaseException:
            self._end('startup_unknown')
            raise

    def _end(self, reason):
        with self.state_lock:
            self.closed = True
            # Separate delivery evidence cannot overwrite the owner's actual result.
            path = self.directory / 'delivery.json'
            if not path.exists():
                owner.private_write(path, {'delivery': 'unknown', 'reason': reason})
            if self.ipc is not None:
                try:
                    self.ipc.shutdown(socket.SHUT_RDWR)
                except OSError:
                    pass
                self.ipc.close()

    def _accept(self):
        while not self.closed:
            if time.monotonic() >= self.deadline:
                self._end('lease_expired')
                break
            try:
                conn, _ = self.listener.accept()
            except socket.timeout:
                continue
            except OSError:
                break
            if not self.slots.acquire(blocking=False):
                conn.close()
                continue
            with self.state_lock:
                self.connections.add(conn)
                thread = threading.Thread(target=self._serve, args=(conn,), daemon=True)
                self.threads.add(thread)
            thread.start()
        if self.listener:
            self.listener.close()

    def _read(self, conn):
        deadline = time.monotonic() + 2
        data = bytearray()
        while b'\r\n\r\n' not in data:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise Refused()
            conn.settimeout(remaining)
            part = conn.recv(1)
            if not part:
                raise EOFError()
            data.extend(part)
            if len(data) > 16384:
                raise Refused('oversized', 413)
        try:
            lines = data[:-4].decode('ascii').split('\r\n')
            method, path, version = lines[0].split(' ')
        except (ValueError, UnicodeError):
            raise Refused() from None
        if version != 'HTTP/1.1':
            raise Refused()
        if method != 'POST':
            raise Refused('method', 405)
        if path != '/tool':
            raise Refused('not_found', 404)
        if len(lines) - 1 > 32:
            raise Refused()
        headers = {}
        allowed = {'host', 'content-type', 'content-length', 'x-mo-workspace-token', 'connection'}
        for line in lines[1:]:
            if ':' not in line:
                raise Refused()
            key, value = line.split(':', 1)
            key = key.lower()
            if key not in allowed or key in headers or any(ord(char) < 32 for char in value):
                raise Refused()
            headers[key] = value.strip(' ')
        if headers.get('host') != f'127.0.0.1:{self.port}':
            raise Refused('unbound', 403)
        if not hmac.compare_digest(headers.get('x-mo-workspace-token', ''), self.token):
            raise Refused('unauthorized', 401)
        if headers.get('content-type') != 'application/json':
            raise Refused('unsupported_media', 415)
        if 'connection' in headers and headers['connection'].lower() != 'close':
            raise Refused()
        length = headers.get('content-length', '')
        if not re.fullmatch(r'[1-9][0-9]{0,8}', length):
            raise Refused()
        length = int(length)
        if length > REQUEST_CAP:
            raise Refused('oversized', 413)
        data = bytearray()
        while len(data) < length:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise Refused()
            conn.settimeout(remaining)
            part = conn.recv(min(65536, length - len(data)))
            if not part:
                raise EOFError()
            data.extend(part)
        return request(bytes(data), self.run_id, self.workspace_id)

    def _dispatch(self, conn, req):
        if not self.lock.acquire(blocking=False):
            return 409, envelope(req, error='busy')
        try:
            if req['call_id'] in self.calls:
                return 409, envelope(req, error='conflict')
            if self.closed or time.monotonic() >= self.deadline:
                return 409, envelope(req, error='admission_closed')
            if len(self.calls) >= 16:
                return 409, envelope(req, error='call_limit')
            readable, _, _ = select.select([conn], [], [], 0)
            if readable:
                # Refuse already-observed EOF/pipelining before dispatch.
                self._end('premature_request_end')
                return 409, envelope(req, error='admission_closed')
            self.calls.add(req['call_id'])
            limit = 300 if req['operation'] == 'command' else 2
            deadline = min(self.deadline, time.monotonic() + limit)
            try:
                self.ipc.settimeout(max(.001, deadline - time.monotonic()))
                owner.send(self.ipc, {'kind': 'tool', 'request': req})
                while True:
                    remaining = deadline - time.monotonic()
                    if remaining <= 0:
                        self._end('response_timeout')
                        return 504, envelope(req, accepted=True, state='timeout', execution='unknown', error='response_timeout')
                    readable, _, _ = select.select([self.ipc, conn], [], [], min(.05, remaining))
                    if conn in readable:
                        if not conn.recv(1, socket.MSG_PEEK):
                            self._end('observed_disconnect')
                            raise EOFError()
                        self._end('unexpected_pipelining')
                        raise EOFError()
                    if self.ipc in readable:
                        self.ipc.settimeout(max(.001, deadline - time.monotonic()))
                        result = owner.receive(self.ipc)
                        response = result['response']
                        if response['execution'] == 'unknown':
                            self._end('unknown_execution')
                        return result['status'], response
            except socket.timeout:
                self._end('response_timeout')
                return 504, envelope(req, accepted=True, state='timeout', execution='unknown', error='response_timeout')
            except (OSError, EOFError, ValueError, KeyError):
                self._end('owner_unknown')
                return 200, envelope(req, accepted=True, state='failure', execution='unknown', error='owner_unknown')
        finally:
            self.lock.release()

    def _serve(self, conn):
        req = None
        response = None
        try:
            req = self._read(conn)
            status, response = self._dispatch(conn, req)
        except Refused as exc:
            status, response = exc.status, envelope(error=exc.error)
        except (OSError, EOFError):
            status, response = 400, envelope(error='malformed')
        try:
            raw = encode(response)
            headers = f'HTTP/1.1 {status} Result\r\nContent-Type: application/json\r\nContent-Length: {len(raw)}\r\nConnection: close\r\n\r\n'.encode('ascii')
            write_deadline = time.monotonic() + 2
            conn.settimeout(2)
            conn.sendall(headers + raw)
            # Half-close delivers the framed refusal even with unread request bytes.
            # Drain only within the same fixed write/close allowance.
            conn.shutdown(socket.SHUT_WR)
            drain_deadline = write_deadline
            remaining_bytes = REQUEST_CAP + 16384
            while remaining_bytes > 0:
                remaining = drain_deadline - time.monotonic()
                if remaining <= 0:
                    break
                conn.settimeout(remaining)
                chunk = conn.recv(min(65536, remaining_bytes))
                if not chunk:
                    break
                remaining_bytes -= len(chunk)
        except OSError:
            if response and response['accepted']:
                self._end('response_write_unknown')
        finally:
            conn.close()
            with self.state_lock:
                self.connections.discard(conn)
                self.threads.discard(threading.current_thread())
            self.slots.release()

    def _operator(self, kind):
        self.closed = True  # Close admission before waiting on the active operation.
        with self.lock:
            self.ipc.settimeout(300)
            owner.send(self.ipc, {'kind': kind})
            return owner.receive(self.ipc)['operator_result']

    def freeze(self):
        return self._operator('freeze')

    def verify(self):
        return self._operator('verify')

    def close(self, seconds=60):
        self._end('operator_close')
        if self.process is None:
            return True
        try:
            self.process.wait(timeout=seconds)
        except subprocess.TimeoutExpired:
            return False
        if hasattr(self, 'accept_thread'):
            self.accept_thread.join(timeout=2)
        return True

    def recover(self):
        if self.process is None or self.process.poll() is None:
            raise RuntimeError('owner death not proved')
        from recovery import recover
        result = recover(self.directory / 'workspace' / 'ownership.json', seconds=60)
        owner.private_write(self.directory / ('cleanup-recovery-' + uuid.uuid4().hex + '.json'), result)
        return result

    def stop_owner(self):
        if self.process is None or self.process.poll() is not None:
            return
        self._end('operator_stop')
        self.process.kill()
        self.process.wait(timeout=2)
