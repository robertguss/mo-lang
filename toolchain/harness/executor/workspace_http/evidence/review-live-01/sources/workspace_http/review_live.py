"""Actual-controller extensions of existing deadlines/shutdown groups.

The lease control deliberately advances only the frontend test deadline after
actual registration. It tests the expiry/IPC race, not a 900-second soak.
"""
import json
from pathlib import Path
import sys
import time
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from workspace_http import Bridge
from workspace_http.live import start_recorded, request, connect, response, registered, shared, require
from workspace_http.owner import private_write
from recovery.live import inventory
from remote import IMAGE, WORKSPACE_POLICY


def main(output):
    output.mkdir(parents=True, exist_ok=False)
    before = shared()
    (output / 'shared-before.txt').write_bytes(before)
    bridges, rows = [], []
    try:
        for group in ('shutdown', 'deadlines'):
            b = Bridge('review-' + group, output / group, {'answer': b'ok\n'},
                       selection={'policy': WORKSPACE_POLICY, 'image': IMAGE, 'toolchain': None},
                       verifier={'script': 'cat /workspace/answer', 'seconds': 1,
                                 'checks': [{'id': 'ok', 'stream': 'stdout', 'mode': 'exact', 'expected': 'ok\n'}]})
            bridges.append(b)
            start_recorded(b)
            if group == 'shutdown':
                first = connect(b, request(b))
                try:
                    first.settimeout(3)
                    header = bytearray()
                    while b'\r\n\r\n' not in header:
                        header.extend(first.recv(1))
                    size = int(next(line.split(b':', 1)[1] for line in header.split(b'\r\n')
                                    if line.startswith(b'Content-Length:')))
                    body = bytearray()
                    while len(body) < size:
                        body.extend(first.recv(size - len(body)))
                    require(json.loads(body)['state'] == 'success')
                    time.sleep(1.5)
                    second = connect(b, request(b, 'command', {'command': 'sleep 1; echo SECOND', 'timeout_ms': 2000}))
                    status, result = response(second)
                    require(status == 200 and result['state'] == 'success' and result['result']['stdout'] == 'SECOND\n', result)
                    require(not b.closed, 'first drain revoked run')
                    rows.append({'group': group, 'held_open_first_response': True, 'second_result': result})
                finally:
                    first.close()
            else:
                conn = connect(b, request(b, 'command', {'command': 'sleep 4; echo AFTER', 'timeout_ms': 6000}))
                registered(b.directory)
                original = b.deadline
                b.deadline = time.monotonic() + .25
                private_write(b.directory / 'test-deadline-override.json', {
                    'original': original, 'test_deadline': b.deadline, 'only_frontend_clock_advanced': True,
                    'full_900_second_soak': False})
                status, result = response(conn)
                require(status == 504 and result['error'] == 'response_timeout' and result['execution'] == 'unknown', result)
                require(b.closed)
                rows.append({'group': group, 'status': status, 'response': result})
            require(b.close())
            actual = json.loads((b.directory / 'owner.json').read_bytes())
            require(actual['cleanup']['cleanup'] == 'confirmed')
            require(all(row['result']['execution'] == 'completed' for row in actual['calls'].values()))
    finally:
        private_write(output / 'results.json', rows)
        receipts = []
        for b in bridges:
            if not b.close():
                b.stop_owner()
            require(b.recover()['cleanup'] == 'confirmed')
            receipts.append(json.loads((b.directory / 'workspace/ownership.json').read_bytes()))
        proof = inventory(receipts)
        private_write(output / 'absence.json', proof)
        require(all(not row['root_exists'] and not row['mounts'] and all(
            not e['root_exists'] and not e['containers'].strip() and not e['units'].strip() and not e['cgroup_exists']
            for e in row['executions']) for row in proof), proof)
        after = shared()
        (output / 'shared-after.txt').write_bytes(after)
        require(len(before.splitlines()) == 5 and sorted(before.splitlines()) == sorted(after.splitlines()))
    print('existing-group real review extensions: 2/2; no acceptance claim')

if __name__ == '__main__':
    main(Path(sys.argv[1]).resolve())
