"""Retain the outer guard exit and clean an interrupted lead check's groups."""
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
mode, name, worker = sys.argv[1:]
assert mode in ('local', 'recovery', 'full') and re.fullmatch('[a-z0-9-]+', name)
assert re.fullmatch('[0-9a-f]{40}', worker)
seconds = {'local': 240, 'recovery': 1800, 'full': 1200}[mode]
out = HERE / name
assert not out.exists()
receipt = HERE / ('launch-' + name)
receipt.mkdir(exist_ok=False)
argv = ['python3', str(ROOT / 'toolchain/bench/step36/guard.py'), str(seconds),
        '--', 'python3', str(HERE / 'accept.py'), mode, name, worker]
started = time.time()
with (receipt / 'stdout.txt').open('xb') as stdout, (receipt / 'stderr.txt').open('xb') as stderr:
    p = subprocess.Popen(argv, cwd=ROOT, stdout=stdout, stderr=stderr, start_new_session=True)
    forced = False
    try:
        code = p.wait(timeout=seconds + 20)
    except subprocess.TimeoutExpired:
        code, forced = 124, True
    except KeyboardInterrupt:
        code, forced = 130, True
    finally:
        interrupted = []
        for path in out.glob('*.started.json'):
            if path.with_name(path.name.replace('.started.json', '.status.json')).exists():
                continue
            group = json.loads(path.read_text())['group']
            try:
                os.killpg(group, signal.SIGKILL)
                interrupted.append(group)
            except ProcessLookupError:
                pass
        try:
            os.killpg(p.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        p.wait(timeout=5)
time.sleep(.2)
groups = {p.pid, *(json.loads(path.read_text())['group'] for path in out.glob('*.started.json'))}
snapshot = subprocess.check_output(['ps', '-axo', 'pid=,pgid=,command='], text=True)
remaining = [row for row in snapshot.splitlines() if len(row.split(None, 2)) == 3 and int(row.split(None, 2)[1]) in groups]
(receipt / 'processes.txt').write_text(snapshot)
record = {'argv': argv, 'exit': code, 'forced': forced, 'started': started, 'finished': time.time(),
          'groups': sorted(groups), 'interrupted_groups_killed': interrupted, 'remaining': remaining}
(receipt / 'receipt.json').write_text(json.dumps(record, indent=2))
size = sum(path.lstat().st_size for base in (receipt, out) for path in base.rglob('*') if path.is_file())
assert size <= 16 * 1024 * 1024, size
print(json.dumps({'exit': code, 'groups_absent': not remaining, 'retained_bytes': size}), flush=True)
assert not forced and not remaining
sys.exit(code)
