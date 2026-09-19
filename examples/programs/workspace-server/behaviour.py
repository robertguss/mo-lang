"""behaviour.py --target CMD [--groups G,...] [--half-close]: local.py's groups, unchanged, against
a server of the same wire. With --half-close every request the groups' client sends is
followed by shutdown(SHUT_WR), a legal HTTP/1.1 half-close (review finding H2), because Mo's
Conn reads only whole lines: a Content-Length body with no newline after it is readable only
once the peer ends its side (REPORT.md, finding F1). Nothing any test expects is changed."""
from pathlib import Path
import socket
import sys

EXECUTOR = Path(__file__).resolve().parents[3] / 'toolchain/harness/executor'
sys.path.insert(0, str(EXECUTOR))
sys.path.insert(0, str(EXECUTOR / 'workspace_http'))

from workspace_http import client  # noqa: E402
import local  # noqa: E402


def half_closing(connect):
    def wrapped(bridge, body, **framing):
        conn = connect(bridge, body, **framing)
        conn.shutdown(socket.SHUT_WR)
        return conn
    return wrapped


if __name__ == '__main__':
    argv = sys.argv[1:]
    if '--half-close' in argv:
        argv.remove('--half-close')
        client.connect = half_closing(client.connect)
        print('HALF-CLOSING CLIENT: SHUT_WR after every request body; expectations unchanged', flush=True)
    sys.argv = [str(EXECUTOR / 'workspace_http/local.py')] + argv
    local.main()
