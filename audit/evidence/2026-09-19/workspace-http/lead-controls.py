"""Independent real HTTP controls: post-dispatch pipelining and core JSON bounds."""
import base64
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / 'toolchain/harness/executor'))
from workspace_http import Bridge
from workspace_http import live, protocol
from recovery.live import inventory, IMAGE as APP_IMAGE, TOOLCHAIN
from remote import IMAGE, WORKSPACE_POLICY

out = Path(sys.argv[1]).resolve()
out.mkdir(exist_ok=False)
bridges, results = [], []
def save(name, value):
    (out / name).write_text(json.dumps(value, indent=2)+'\n')
def shared():
    p = subprocess.run(['docker', '--context', 'orbstack', 'ps', '-a', '--no-trunc',
                        '--format', '{{.ID}} {{.State}}'], capture_output=True, timeout=10, check=True)
    return sorted(p.stdout.decode().splitlines())
def new(name, application=False):
    selection = ({'policy': 'application-build-v1', 'image': APP_IMAGE, 'toolchain': TOOLCHAIN}
                 if application else {'policy': WORKSPACE_POLICY, 'image': IMAGE, 'toolchain': None})
    bridge = Bridge('lead-' + name, out / name, {'small': b'baseline\n'}, selection=selection,
                    verifier={'script': 'cat /workspace/small', 'seconds': 2,
                              'checks': [{'id': 'small', 'stream': 'stdout', 'mode': 'exact',
                                          'expected': 'baseline\n'}]})
    bridges.append(bridge)
    return live.start_recorded(bridge)
def frame(bridge, req):
    raw = protocol.encode(req)
    return (f'POST /tool HTTP/1.1\r\nHost: 127.0.0.1:{bridge.port}\r\n'
            f'Content-Type: application/json\r\nContent-Length: {len(raw)}\r\n'
            f'X-Mo-Workspace-Token: {bridge.token}\r\n\r\n').encode()+raw
before = shared()
assert len(before) == 5
save('shared-before.json', before)
try:
    b = new('pipeline')
    script = "set -eu; printf 'lead-pipeline\\n' > first-marker; sleep 3; test ! -e second-marker; cat first-marker"
    first = live.request(b, 'command', {'command': script, 'timeout_ms': 5000}, 'first')
    conn = live.connect(b, first)
    try:
        live.registered(b.directory)
        second = live.request(b, 'write_file', {'path': 'second-marker', 'text': 'must-not-execute'}, 'second')
        conn.sendall(frame(b, second))
        status, response = live.response(conn)
    finally:
        conn.close()
    assert status == 200 and response['execution'] == 'unknown' and b.closed, (status, response)
    journal = live.finished(b.directory)
    assert set(journal['calls']) == {'first'}, journal['calls']
    actual = journal['calls']['first']['result']
    assert actual['execution'] == 'completed' and actual['state'] == 'success'
    assert actual['result']['exit_code'] == 0 and actual['result']['stdout'] == 'lead-pipeline\n', actual
    core_id = journal['calls']['first']['core_call_id']
    core = json.loads((b.directory / ('core-' + core_id + '.json')).read_bytes())
    assert core['execution_valid'] is True and core['exit_code'] == 0
    assert base64.b64decode(core['stdout'], validate=True) == b'lead-pipeline\n'
    assert b.close()
    results.append({'case': 'post-dispatch-pipeline', 'passed': True, 'wire': response,
                    'actual_first': actual, 'claims': 1, 'second_claimed': False,
                    'original_cleanup': journal['cleanup']})
    save('results-before-cleanup.json', results)

    b = new('escaped-size', application=True)
    text = '☃' * 12000
    assert len(text.encode()) == 36000 and len(json.dumps(text).encode()) > 65280
    written = live.call(b, 'write_file', {'path': 'escaped', 'text': text}, 'write')
    refused = live.call(b, 'read_file', {'path': 'escaped'}, 'read')
    later = live.call(b, 'read_file', {'path': 'small'}, 'later')
    assert written[0] == 200 and written[1]['state'] == 'success', written
    assert refused[0] == 200 and refused[1]['state'] == 'refusal', refused
    assert refused[1]['error'] == 'result_too_large' and refused[1]['execution'] == 'completed', refused
    assert later[0] == 200 and later[1]['result']['text'] == 'baseline\n' and not b.closed, later
    assert b.close()
    journal = json.loads((b.directory / 'owner.json').read_bytes())
    assert journal['cleanup']['cleanup'] == 'confirmed'
    assert set(journal['calls']) == {'write', 'read', 'later'}
    results.append({'case': 'escaped-core-limit', 'passed': True, 'source_utf8_bytes': 36000,
                    'json_string_bytes': len(json.dumps(text).encode()), 'written': written,
                    'refused': refused, 'later': later, 'claims': 3,
                    'original_cleanup': journal['cleanup']})
finally:
    save('results-before-cleanup.json', results)
    cleanup = []
    receipts = []
    for b in bridges:
        if not b.close(seconds=65):
            b.stop_owner()
        receipt = b.directory / 'workspace/ownership.json'
        if receipt.exists():
            proof = b.recover()
            cleanup.append(proof)
            receipts.append(json.loads(receipt.read_bytes()))
    save('cleanup.json', cleanup)
    assert cleanup and all(r['cleanup'] == 'confirmed' and r['execution'] == 'unknown' for r in cleanup)
    proof = inventory(receipts)
    save('absence.json', proof)
    assert all(not r['root_exists'] and not r['mounts'] and all(
        not e['root_exists'] and not e['containers'].strip() and not e['units'].strip()
        and not e['cgroup_exists'] for e in r['executions']) for r in proof)
    after = shared(); save('shared-after.json', after)
    assert before == after
assert len(results) == 2 and all(r['passed'] for r in results)
save('results.json', results)
print(json.dumps({'cases': 2, 'passed': 2, 'real_http_and_workspace': True}))
