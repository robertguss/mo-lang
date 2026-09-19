"""Actual-controller extensions of existing deadlines/shutdown groups.

The lease control deliberately advances only the frontend test deadline before
HTTP dispatch, then confirms actual registration. It tests the expiry/IPC race, not a 900-second soak.
"""
import json
from pathlib import Path
import sys
import time
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import cases
from cases import require
from workspace_http import Bridge
from workspace_http.client import connect, first_response, request
from workspace_http.live import registered, response, start_recorded
from workspace_http.owner import private_write
from remote import IMAGE, WORKSPACE_POLICY


def main(output):
    output.mkdir(parents=True, exist_ok=False)
    before = cases.mac_docker()
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
                    require(first_response(first)['state'] == 'success')
                    time.sleep(1.5)
                    second = connect(b, request(b, 'command', {'command': 'sleep 1; echo SECOND', 'timeout_ms': 2000}))
                    status, result = response(second)
                    require(status == 200 and result['state'] == 'success' and result['result']['stdout'] == 'SECOND\n', result)
                    require(not b.closed, 'first drain revoked run')
                    rows.append({'group': group, 'held_open_first_response': True, 'second_result': result})
                finally:
                    first.close()
            else:
                original = b.deadline
                b.deadline = time.monotonic() + 1
                conn = connect(b, request(b, 'command', {'command': 'sleep 4; echo AFTER', 'timeout_ms': 6000}))
                registered(b.directory)
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
        proof = cases.workspace_absence(receipts)
        private_write(output / 'absence.json', proof)
        cases.require_absent(proof)
        after = cases.mac_docker()
        (output / 'shared-after.txt').write_bytes(after)
        require(len(before.splitlines()) == 5 and sorted(before.splitlines()) == sorted(after.splitlines()))
    print('existing-group real review extensions: 2/2; no acceptance claim')

if __name__ == '__main__':
    main(Path(sys.argv[1]).resolve())
