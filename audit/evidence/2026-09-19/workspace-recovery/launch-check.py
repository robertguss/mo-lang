"""Force the real guard to kill a stub owner; require its child group cleanup."""
import json
from pathlib import Path
import runpy
import subprocess
import sys
import tempfile
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
name = 'outer-fault-01'
out = HERE / name
original = subprocess.Popen
injected = []
stub = '''import json,subprocess,sys,time
from pathlib import Path
out=Path(sys.argv[1]);out.mkdir()
p=subprocess.Popen([sys.executable,'-c','import time; time.sleep(300)'],start_new_session=True)
(out/'interrupted.started.json').write_text(json.dumps({'group':p.pid,'argv':[sys.executable,'-c','import time; time.sleep(300)']}))
time.sleep(300)
'''
with tempfile.TemporaryDirectory(prefix='mo-lead-launch-check-') as temp:
    child = Path(temp) / 'stub.py'
    child.write_text(stub)

    def spawn(argv, *args, **kwargs):
        if isinstance(argv, list) and len(argv) > 2 and argv[1] == str(ROOT / 'toolchain/bench/step36/guard.py'):
            argv = [sys.executable, argv[1], '1', '--', sys.executable, str(child), str(out)]
            injected.append(argv)
        return original(argv, *args, **kwargs)

    sys.argv = [str(HERE / 'launch.py'), 'local', name, 'df816be3aabf3d308482e4f2f09830ebdb604be1']
    with patch.object(subprocess, 'Popen', side_effect=spawn):
        try:
            runpy.run_path(str(HERE / 'launch.py'), run_name='__main__')
        except SystemExit as exc:
            code = exc.code
        else:
            raise AssertionError('launcher did not exit')
    receipt = json.loads((HERE / ('launch-' + name) / 'receipt.json').read_text())
    assert len(injected) == 1 and code == receipt['exit'] == 137, receipt
    assert len(receipt['interrupted_groups_killed']) == 1 and not receipt['remaining'], receipt
    (out / 'fault-proof.json').write_text(json.dumps({'expected_outer_exit': 137,
        'actual_guard_argv': injected[0], 'stub_source': stub,
        'owned_child_group_killed': True, 'remaining': [], 'passed': True}, indent=2))
print(json.dumps({'passed': 1, 'expected': 1, 'guard_killed_owner': True, 'owned_child_absent': True}))
