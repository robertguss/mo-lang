"""Fresh read-only lead readiness before explicit HTTP-worker machine release."""
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess

root = Path(__file__).resolve().parents[4]
out = Path(__file__).parent / 'preflight-01'
out.mkdir()
script = root / 'audit/evidence/2026-09-19/workspace-recovery/inventory.py'
(out / 'inventory-source.py').write_bytes(script.read_bytes())
argv = ['python3', str(root / 'toolchain/bench/step36/guard.py'), '60', '--',
        'python3', '-B', str(script), str(out), '--readiness']
p = subprocess.Popen(argv, cwd=root, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                     start_new_session=True)
try:
    stdout, stderr = p.communicate(timeout=70)
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
receipt = {'argv': argv, 'exit': p.returncode, 'group': p.pid,
           'group_remaining': remaining,
           'source_sha256': hashlib.sha256(script.read_bytes()).hexdigest()}
(out / 'receipt.json').write_text(json.dumps(receipt, indent=2))
assert p.returncode == 0 and not remaining
inventory = json.loads((out / 'readiness-inventory.json').read_text())
assert not inventory['containers']['stdout'].strip()
assert not inventory['units']['stdout'].strip()
print(json.dumps({'ready': True, 'containers': 0, 'units': 0, 'parent_tasks': 0,
                  'actual_exit': p.returncode, 'group_remaining': remaining}))
