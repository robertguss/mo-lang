"""Run an immutable, bounded attempt with repository guard and group cleanup."""
import json
import hashlib
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

root = Path(sys.argv[1])
seconds = int(sys.argv[2])
if not 1 <= seconds <= 1800 or len(sys.argv) < 4:
    raise SystemExit('expected attempt path, 1..1800 seconds, command')
root.mkdir(parents=True, exist_ok=False)
cmd = [sys.executable, '-B', 'toolchain/bench/step36/guard.py', str(seconds), '--', *sys.argv[3:]]
(root / 'command.json').write_text(json.dumps({'argv': cmd, 'cwd': os.getcwd()}))
(root / 'head.txt').write_bytes(subprocess.check_output(['git', 'rev-parse', 'HEAD']))
sources = Path('toolchain/harness/executor')
identities = {}
for path in [*sources.glob('*.py'), *(sources / 'application').glob('*.py'), sources / 'application/Dockerfile']:
    data = path.read_bytes()
    relative = path.relative_to(sources)
    target = root / 'sources' / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(data)
    identities[str(path)] = hashlib.sha256(data).hexdigest()
(root / 'source-identities.json').write_text(json.dumps(identities, indent=2))
start = time.monotonic()
rc = 124
next_size_check = 0
with (root / 'output.txt').open('xb') as out:
    p = subprocess.Popen(cmd, stdout=out, stderr=subprocess.STDOUT, start_new_session=True)
    try:
        while p.poll() is None:
            if time.monotonic() - start > seconds + 10 or out.tell() > 16 * 1024 * 1024:
                break
            if time.monotonic() >= next_size_check:
                if sum(path.stat().st_size for path in root.rglob('*') if path.is_file()) > 16 * 1024 * 1024:
                    break
                next_size_check = time.monotonic() + 1
            time.sleep(.1)
        if p.poll() is not None:
            rc = p.returncode
    finally:
        try:
            os.killpg(p.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        p.wait(timeout=3)
remaining = subprocess.check_output(['ps', '-axo', 'pid=,pgid=,command=']).decode()
rows = [line for line in remaining.splitlines() if line.split()[1] == str(p.pid)]
result = {'exit': rc, 'elapsed_seconds': time.monotonic() - start,
          'process_group': p.pid, 'remaining_processes': rows,
          'output_bytes': (root / 'output.txt').stat().st_size,
          'retained_bytes': sum(path.stat().st_size for path in root.rglob('*') if path.is_file())}
(root / 'result.json').write_text(json.dumps(result, indent=2))
print((root / 'output.txt').read_text(errors='replace'))
print(json.dumps(result), flush=True)
sys.exit(rc if not rows and result['retained_bytes'] <= 16 * 1024 * 1024 else 1)
