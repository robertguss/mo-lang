"""The fixed group registry and a minimal HTTP/1.1 client, shared by the local and live suites."""
import json
import socket
import uuid

from cases import require
from . import protocol as wire

GROUPS = ('six-tools', 'output-encoding', 'schema', 'framing', 'byte-bounds',
          'identities-capability', 'duplicate-calls', 'concurrent-admission',
          'file-refusals', 'deadlines', 'disconnect', 'frontend-death', 'owner-death',
          'lost-response', 'owner-stall', 'startup-failure', 'shutdown',
          'protected-verifier', 'application-binding', 'cleanup-outcome',
          'invalid-selection', 'journal-order-bound')


def request(bridge, operation='list_files', args=None, call_id=None):
    return dict(version=wire.VERSION, run_id=bridge.run_id, workspace_id=bridge.workspace_id,
                call_id=call_id or uuid.uuid4().hex, operation=operation, args=args or {})


def connect(bridge, body, *, extra='', token=None, first='POST /tool HTTP/1.1', length=None, timeout=5):
    """Sends one request; `body` is a request dict or raw bytes, the rest bends the framing."""
    conn = socket.create_connection(('127.0.0.1', bridge.port), timeout=timeout)
    raw = body if isinstance(body, bytes) else wire.encode(body)
    conn.sendall((f'{first}\r\nHost: 127.0.0.1:{bridge.port}\r\nContent-Type: application/json\r\n'
                  f'Content-Length: {len(raw) if length is None else length}\r\n'
                  f'X-Mo-Workspace-Token: {bridge.token if token is None else token}\r\n{extra}\r\n').encode() + raw)
    return conn


def response(conn, timeout):
    """Reads to EOF and closes. The reply must be framed, marked close and within the cap."""
    conn.settimeout(timeout)
    raw = bytearray()
    try:
        while True:
            part = conn.recv(65536)
            if not part:
                break
            raw.extend(part)
            require(len(raw) <= wire.RESPONSE_CAP + 1024, 'wire response bound')
    finally:
        conn.close()
    head, body = bytes(raw).split(b'\r\n\r\n', 1)
    require(f'Content-Length: {len(body)}'.encode() in head, 'response length')
    require(b'Connection: close' in head, 'response close')
    require(len(body) <= wire.RESPONSE_CAP, 'response body bound')
    return int(head.split(b' ')[1]), json.loads(body)


def first_response(conn, timeout=3):
    """One response body, read by its Content-Length, leaving the connection open."""
    conn.settimeout(timeout)
    head = bytearray()
    while b'\r\n\r\n' not in head:
        part = conn.recv(1)
        require(part, 'closed before the response headers')
        head.extend(part)
    size = int(next(line.split(b':', 1)[1] for line in bytes(head).split(b'\r\n') if line.startswith(b'Content-Length:')))
    body = bytearray()
    while len(body) < size:
        body.extend(conn.recv(size - len(body)))
    return json.loads(body)
