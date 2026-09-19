"""Local socketpair dispatch deadline probe; no Workspace or machine effect."""
import json
from pathlib import Path
import socket
import struct
import sys
import tempfile
import threading
import time
source, out = map(Path, sys.argv[1:3])
sys.path.insert(0, str(source / 'toolchain/harness/executor'))
from workspace_http import owner, protocol
from workspace_http.bridge import Bridge
out.mkdir()
with tempfile.TemporaryDirectory() as temporary:
    b = Bridge.__new__(Bridge)
    b.directory = Path(temporary)
    b.lock, b.state_lock = threading.Lock(), threading.Lock()
    b.calls, b.closed = set(), False
    b.deadline = time.monotonic() + 900
    b.ipc, peer = socket.socketpair()
    conn, client = socket.socketpair()
    req = dict(version=protocol.VERSION, run_id='probe', workspace_id='a'*32,
               call_id='first', operation='list_files', args={})
    response = protocol.envelope(req, accepted=True, state='success', execution='completed',
                                 result={'items': [], 'truncated': False})
    send_errors = []
    def fragmented_reply():
        try:
            peer.settimeout(4)
            owner.receive(peer)
            raw = protocol.encode({'status': 200, 'response': response})
            peer.sendall(struct.pack('!I', len(raw)) + raw[:1])
            for start, end in ((1,2),(2,3),(3,len(raw))):
                time.sleep(.8)
                peer.sendall(raw[start:end])
        except OSError as exc:
            send_errors.append(type(exc).__name__)
        finally:
            peer.close()
    thread = threading.Thread(target=fragmented_reply)
    thread.start()
    started = time.monotonic()
    try:
        status, result = b._dispatch(conn, req)
        elapsed = time.monotonic() - started
        passed = status == 504 and result['execution'] == 'unknown' and elapsed < 2.3 and b.closed
        row = dict(status=status, result=result, elapsed_seconds=elapsed, configured_file_wait=2,
                   admission_closed=b.closed, passed=passed, local_socketpair_only=True, machine_calls=0)
    finally:
        b.ipc.close(); conn.close(); client.close()
        thread.join(timeout=4)
        assert not thread.is_alive()
    row['sender_errors'] = send_errors
    (out/'results.json').write_text(json.dumps(row, indent=2)+'\n')
    print(json.dumps(row))
raise SystemExit(0 if passed else 1)
