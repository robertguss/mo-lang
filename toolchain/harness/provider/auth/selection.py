"""Runner selection failures are expected and retained verbatim."""
import json, pathlib, subprocess, sys
root = pathlib.Path(__file__).resolve().parent
runtime = sys.argv[1]
names = (root/'controls.txt').read_text().split()
for selection in ([], ['unknown_control'], [names[0], names[0]], names+[names[0]]):
    command = ['node', 'test.mjs', runtime, *selection]
    result = subprocess.run(command, cwd=root, capture_output=True, text=True, timeout=20)
    print(json.dumps({'command':command,'exit':result.returncode,'stdout':result.stdout,'stderr':result.stderr}),flush=True)
    assert result.returncode == 2 and result.stdout == 'invalid_control_selection\n' and not result.stderr
print('PASS empty, unknown, duplicate, excessive selections rejected')
