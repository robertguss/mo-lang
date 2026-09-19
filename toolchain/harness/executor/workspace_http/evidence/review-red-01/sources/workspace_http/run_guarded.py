"""Immutable per-attempt logs, numeric guard, and owned process-group cleanup."""
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

seconds = int(sys.argv[1])
assert 0 < seconds <= 1800
output = Path(sys.argv[2])
output.mkdir(parents=True, exist_ok=False)
cmd = sys.argv[3:]
(output / 'command.json').write_text(json.dumps(cmd))
sources = Path('toolchain/harness/executor').resolve()
identities = {}
for path in [*(sources / name for name in ('workspace.py', 'workspace_controller.py', 'adapter.py', 'remote.py', 'workspace_files.py')), *Path(__file__).parent.glob('*.py'), *Path(__file__).parent.glob('*.md')]:
    data = path.read_bytes()
    relative = path.relative_to(sources)
    target = output / 'sources' / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(data)
    identities[str(relative)] = hashlib.sha256(data).hexdigest()
(output / 'source-identities.json').write_text(json.dumps(identities, indent=2))
(output / 'head.txt').write_bytes(subprocess.check_output(['git', 'rev-parse', 'HEAD']))
def retained_bytes():
    return sum(path.lstat().st_size for path in output.rglob('*') if path.is_file())

start = time.monotonic()
with (output / 'output.log').open('xb') as log:
    p = subprocess.Popen([sys.executable, 'toolchain/bench/step36/guard.py', str(seconds), '--', *cmd],
                         stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
    try:
        while p.poll() is None:
            if time.monotonic() - start > seconds + 5 or retained_bytes() > 16 * 1024 * 1024:
                raise TimeoutError('attempt limit')
            time.sleep(.1)
        code = p.returncode
    except BaseException:
        code = 124
    finally:
        try:
            os.killpg(p.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        p.wait()
end = time.monotonic() + 3
while True:
    snapshot = subprocess.check_output(['ps', '-axo', 'pid=,pgid=,stat=,command='])
    remaining = [line.decode() for line in snapshot.splitlines()
                 if len(line.split(None, 3)) >= 3 and int(line.split(None, 3)[1]) == p.pid]
    if not remaining or time.monotonic() >= end:
        break
    time.sleep(.1)
(output / 'processes.txt').write_bytes(snapshot)
child_exit = code
if remaining or retained_bytes() > 16 * 1024 * 1024:
    code = 125
record = {'exit': code, 'child_exit': child_exit, 'group': p.pid,
          'group_absent': not remaining, 'remaining': remaining,
          'elapsed': time.monotonic() - start, 'total_bytes': 0, 'budget_bytes': 16 * 1024 * 1024}
size = retained_bytes()
for _ in range(4):
    record['total_bytes'] = size + len(json.dumps(record).encode())
(output / 'exit.json').write_text(json.dumps(record))
print(output, 'exit', code, flush=True)
sys.exit(code)
