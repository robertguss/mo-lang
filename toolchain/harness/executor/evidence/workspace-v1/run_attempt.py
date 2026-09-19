"""Numeric repository guard with process-group cleanup and immutable attempt logs."""
import os
from pathlib import Path
import signal
import subprocess
import sys

root = Path(sys.argv[1])
root.mkdir(parents=True, exist_ok=False)
cmd = [sys.executable, 'toolchain/bench/step36/guard.py', '600', '--', *sys.argv[2:]]
(root / 'command.txt').write_text(repr(cmd) + '\n')
with (root / 'output.txt').open('wb') as out:
    p = subprocess.Popen(cmd, stdout=out, stderr=subprocess.STDOUT, start_new_session=True)
    try:
        rc = p.wait(timeout=615)
    finally:
        try:
            os.killpg(p.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        if p.poll() is None:
            p.wait(timeout=3)
(root / 'exit.txt').write_text(str(rc) + '\n')
size = sum(f.stat().st_size for f in root.rglob('*') if f.is_file())
(root / 'retained-bytes.txt').write_text(str(size) + '\n')
print((root / 'output.txt').read_text())
print('attempt exit=' + str(rc) + ' retained_bytes=' + str(size), flush=True)
if size > 16 * 1024 * 1024:
    raise SystemExit('evidence budget exceeded; retained for diagnosis')
sys.exit(rc)
