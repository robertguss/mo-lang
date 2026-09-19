"""Retain one guarded IPC deadline attempt with real exit and owned group proof."""
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import sys

root = Path(__file__).resolve().parents[4]
base = Path(__file__).parent
source, name = sys.argv[1:3]
out = base / name
out.mkdir()
for script in ('ipc-deadline-probe.py', 'run-ipc-deadline-probe.py'):
    (out / script).write_bytes((base / script).read_bytes())
(out / 'SOURCE.json').write_bytes((Path(source) / 'SOURCE.json').read_bytes())
argv = ['python3', str(root / 'toolchain/bench/step36/guard.py'), '30', '--',
        'python3', '-B', str(base / 'ipc-deadline-probe.py'), source, str(out / 'controls')]
p = subprocess.Popen(argv, cwd=root, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                     start_new_session=True)
try:
    stdout, stderr = p.communicate(timeout=40)
finally:
    try:
        os.killpg(p.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    p.wait()
(out / 'stdout.txt').write_bytes(stdout)
(out / 'stderr.txt').write_bytes(stderr)
try:
    os.killpg(p.pid, 0)
    remaining = True
except ProcessLookupError:
    remaining = False
manifest = json.loads((Path(source) / 'SOURCE.json').read_text())
unchanged = all(hashlib.sha256((Path(source) / v['path']).read_bytes()).hexdigest() == v['sha256']
                for v in manifest['files'])
receipt = {'argv': argv, 'exit': p.returncode, 'group': p.pid, 'group_remaining': remaining,
           'source_tip': manifest['tip'], 'snapshot_unchanged': unchanged,
           'probe_sha256': hashlib.sha256((base / 'ipc-deadline-probe.py').read_bytes()).hexdigest()}
(out / 'receipt.json').write_text(json.dumps(receipt, indent=2))
print(json.dumps(receipt))
assert unchanged and not remaining
raise SystemExit(p.returncode)
