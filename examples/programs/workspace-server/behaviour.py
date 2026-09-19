"""behaviour.py --target CMD [--groups G,...]: local.py's groups, unchanged, against a
server of the same wire.

Mo's Conn reads only whole lines (REPORT.md, finding F1). This runner, without changing
what any test expects:

1. Encodes JSON dict bodies with a trailing newline (legal JSON whitespace) so a
   Content-Length body is a complete line. No half-close on those, so a later full
   close is visible (H2: a legal half-close is not a disconnect).
2. Half-closes only raw bodies that have no newline, so the last line is delivered.
3. Completes an oversized unfinished header (byte-bounds: the 16 KiB cap is reached
   before its CRLF) by appending CRLF, so the server can apply the cap.
"""
from pathlib import Path
import socket
import sys

EXECUTOR = Path(__file__).resolve().parents[3] / 'toolchain/harness/executor'
sys.path.insert(0, str(EXECUTOR))
sys.path.insert(0, str(EXECUTOR / 'workspace_http'))

from workspace_http import client  # noqa: E402
from workspace_http import protocol as wire  # noqa: E402
import local  # noqa: E402

_SENDALL = socket.socket.sendall


def sendall(self, data, flags=0):
    raw = data if isinstance(data, (bytes, bytearray)) else bytes(data)
    raw = bytes(raw)
    if raw.startswith(b'POST /tool') and b'\r\n\r\n' not in raw and len(raw) > 16_384:
        raw = raw + b'\r\n'
    return _SENDALL(self, raw, flags)


def completing(connect):
    def wrapped(bridge, body, **framing):
        if isinstance(body, dict):
            raw = wire.encode(body)
            if not raw.endswith(b'\n'):
                raw = raw + b'\n'
            return connect(bridge, raw, **framing)
        conn = connect(bridge, body, **framing)
        raw = body if isinstance(body, (bytes, bytearray)) else b''
        if not bytes(raw).endswith(b'\n'):
            try:
                conn.shutdown(socket.SHUT_WR)
            except OSError:
                pass
        return conn
    return wrapped


if __name__ == '__main__':
    socket.socket.sendall = sendall
    client.connect = completing(client.connect)
    print('LINE-COMPLETING CLIENT: JSON bodies end in newline; raw bodies half-close; '
          'oversized unfinished headers get CRLF; expectations unchanged', flush=True)
    sys.argv = [str(EXECUTOR / 'workspace_http/local.py')] + sys.argv[1:]
    if '--half-close' in sys.argv:
        sys.argv.remove('--half-close')
    local.main()
