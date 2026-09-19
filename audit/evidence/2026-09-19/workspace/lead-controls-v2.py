"""Independent workspace controls for active refusal and executable snapshots."""
import json
from pathlib import Path
import sys
import uuid

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / 'toolchain/harness/executor'))
from adapter import py
from selftest import TREE, assert_clean, snapshot, wait_running
from workspace import Workspace

OUT = Path(sys.argv[1])
OUT.mkdir(exist_ok=False)
results = []
ws = Workspace(uuid.uuid4().hex, OUT / 'active-refusal')
ws.create({'answer.txt': b'unchanged\n'})
try:
    first_id, refused_id = uuid.uuid4().hex, uuid.uuid4().hex
    run = ws.start_command(TREE + 'wait\n', seconds=10, call_id=first_id)
    before = wait_running(run)
    refused = ws.command('', call_id=refused_id)
    assert ws.active is run
    assert refused['state'] == 'refusal' and refused['execution'] == 'not_started'
    assert refused['call_id'] == refused_id and refused['run_id'] == ws.run_id
    assert 'passed' not in refused and not refused['execution_valid']
    after = snapshot(run)
    assert after['containers']['stdout'] == before['containers']['stdout']
    assert after['cgroup_exists'] and after['top']['rc'] == 0
    ws.cancel()
    collected = ws.collect()
    assert collected['state'] == 'cancellation' and collected['call_id'] == first_id, collected
    assert collected['execution_valid']
    cleaned = assert_clean(run)
    assert ws.read_file('answer.txt') == 'unchanged\n'
    results.append({'case': 'refused-second-command-preserves-active-run', 'passed': True, 'before': before,
                    'refused': refused, 'after': after, 'collected': collected, 'cleaned': cleaned})
finally:
    if ws.active:
        ws.cancel()
        ws.collect()
    ws.delete()

ws = Workspace(uuid.uuid4().hex, OUT / 'executable-snapshot')
ws.create({'bin/task': b'x old y\n'})
try:
    assert ws.command('chmod 701 bin/task')['state'] == 'success'
    ws.exact_edit('bin/task', 'old', 'new')
    frozen = ws.freeze()
    row = frozen['inventory']['items'][0]
    assert row['path'] == 'bin/task' and row['mode'] == 0o755 and row['length'] == 8
    check = {'id': 'mode-and-content', 'stream': 'stdout', 'mode': 'exact', 'expected': '755\nx new y\n'}
    verified = ws.verify('stat -c "%a" bin/task; cat bin/task', [check])
    assert verified['passed'] and verified['execution_valid']
    assert verified['manifest']['workspace']['snapshot'] == frozen['snapshot']
    results.append({'case': 'exact-edit-executable-mode-and-snapshot-content', 'passed': True, 'frozen': frozen, 'verified': verified})
finally:
    if ws.active:
        ws.collect()
    ws.delete()

state = json.loads(py('''import json,pathlib,subprocess
base=pathlib.Path('/var/lib/mo-harness')
out={'workspace_directories':[str(p) for p in base.glob('mo-workspace-*') if p.is_dir()]}
for key,args in [('mounts',['findmnt','--json','-o','TARGET']),('containers',['docker','ps','-aq','--filter','name=^/mo-executor-']),('units',['systemctl','list-units','--all','--no-legend','mo-executor-*'])]:
 p=subprocess.run(args,capture_output=True,text=True,timeout=3);out[key]={'rc':p.returncode,'stdout':p.stdout}
print(json.dumps(out))
'''))
assert not state['workspace_directories']
assert state['mounts']['rc'] == 0 and 'mo-workspace-' not in state['mounts']['stdout']
assert all(state[k]['rc'] == 0 and not state[k]['stdout'].strip() for k in ['containers', 'units'])
(OUT / 'results.json').write_text(json.dumps({'controls': results, 'final': state}, indent=2) + '\n')
print(json.dumps({'passed': len(results), 'expected': 2, 'final_empty': True}))
