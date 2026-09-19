"""Independent local HTTP drain controls; explicit subprocess double, no machine."""
import json
from pathlib import Path
import socket
import sys
import time

source, out = map(Path, sys.argv[1:3])
sys.path.insert(0, str(source / 'toolchain/harness/executor'))
from workspace_http.local import Controls

out.mkdir()
rows = []

def complete_response(conn):
    conn.settimeout(4)
    raw = b''
    while b'\r\n\r\n' not in raw:
        part = conn.recv(65536)
        assert part, 'EOF before response headers'
        raw += part
    head, body = raw.split(b'\r\n\r\n', 1)
    lengths = [int(line.split(b':', 1)[1]) for line in head.split(b'\r\n')[1:]
               if line.lower().startswith(b'content-length:')]
    assert len(lengths) == 1
    while len(body) < lengths[0]:
        part = conn.recv(65536)
        assert part
        body += part
    assert len(body) == lengths[0]
    return int(head.split(b' ')[1]), json.loads(body)

for name in ('later-new-call', 'later-active-call'):
    control = Controls()
    control.setUp()
    conn = None
    try:
        bridge = control.bridge()
        assert 'workspace_http.test_owner' in bridge.process.args
        conn = control.connect(bridge, control.req(bridge, call_id='first'))
        first = complete_response(conn)
        assert first[0] == 200 and first[1]['state'] == 'success'
        # Keep the request's sending side open after receiving the complete reply.
        time.sleep(2.4 if name == 'later-new-call' else 1.7)
        second = None
        failure = None
        try:
            second = control.call(bridge, call_id='second',
                                  **({} if name == 'later-new-call' else
                                     {'operation': 'command', 'args': {'command': 'slow', 'timeout_ms': 1000}}))
        except OSError as exc:
            failure = {'type': type(exc).__name__, 'errno': exc.errno}
        row = {'case': name, 'first': first, 'second': second, 'transport_failure': failure,
               'admission_closed': bridge.closed}
        delivery = bridge.directory / 'delivery.json'
        row['delivery'] = json.loads(delivery.read_bytes()) if delivery.exists() else None
        row['passed'] = (second is not None and second[0] == 200
                         and second[1]['state'] == 'success' and not bridge.closed)
        rows.append(row)
    finally:
        if conn is not None:
            conn.close()
        control.tearDown()
(out / 'results.json').write_text(json.dumps(rows, indent=2))
print(json.dumps({'cases': len(rows), 'passed': sum(r['passed'] for r in rows),
                  'subprocess_double_only': True, 'machine_calls': 0}))
raise SystemExit(0 if len(rows) == 2 and all(r['passed'] for r in rows) else 1)
