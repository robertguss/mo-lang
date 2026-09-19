"""Cross-build trusted committed compiler source; no candidate code executes here."""
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tarfile
import tempfile
import time
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent
OUT = HERE / 'cross-build-01'
OUT.mkdir(exist_ok=False)
manifest = json.loads((HERE / 'install-build-01/manifest.json').read_text())
archive = Path(manifest['source_archive'])
assert hashlib.sha256(archive.read_bytes()).hexdigest() == manifest['source_sha256']
copy = Path(tempfile.mkdtemp(prefix='mo-trusted-cross-'))
with tarfile.open(archive) as tar:
    tar.extractall(copy, filter='data')
zig = shutil.which('zig')
assert zig
command = ['python3', str(ROOT / 'toolchain/bench/step36/guard.py'), '900', '--', zig,
           'build', '-j1', '-Dtarget=aarch64-linux-musl']
env = dict(os.environ, ZIG_GLOBAL_CACHE_DIR=str(copy / 'global-zig-cache'))
record = {'source_commit': manifest['commit'], 'source_sha256': manifest['source_sha256'],
          'source_copy': str(copy), 'command': command, 'cwd': str(copy / 'toolchain'),
          'zig': zig, 'target': 'aarch64-linux-musl', 'trusted_compiler_build': True,
          'candidate_execution': False, 'started_et': datetime.now(ZoneInfo('America/New_York')).isoformat()}
(OUT / 'manifest.json').write_text(json.dumps(record, indent=2) + '\n')


def group_rows(pgid):
    rows = subprocess.check_output(['ps', '-axo', 'pid=,pgid=,rss=,command='], text=True).splitlines()
    return [r.strip() for r in rows if len(r.split(None, 3)) == 4 and r.split(None, 3)[1] == str(pgid)]


with (OUT / 'build.stdout.txt').open('w') as out, (OUT / 'build.stderr.txt').open('w') as err:
    p = subprocess.Popen(command, cwd=copy / 'toolchain', env=env, stdout=out, stderr=err, start_new_session=True)
    began = time.monotonic()
    peak = 0
    stopped = None
    while p.poll() is None:
        rows = group_rows(p.pid)
        rss = sum(int(row.split(None, 3)[2]) for row in rows) * 1024
        peak = max(peak, rss)
        if rss > 4 * 1024**3 or time.monotonic() - began > 920:
            stopped = 'group_memory' if rss > 4 * 1024**3 else 'outer_deadline'
            os.killpg(p.pid, signal.SIGKILL)
            break
        time.sleep(.5)
    rc = p.wait(timeout=3)
    before = group_rows(p.pid)
    if before:
        os.killpg(p.pid, signal.SIGKILL)
        time.sleep(1)
    after = group_rows(p.pid)
record.update(exit_code=rc, stop_reason=stopped, peak_group_rss=peak,
              cleanup_before=before, cleanup_after=after,
              finished_et=datetime.now(ZoneInfo('America/New_York')).isoformat())
if rc == 0 and not stopped and not before and not after:
    binary = copy / 'toolchain/zig-out/bin/mo'
    data = binary.read_bytes()
    assert data[:4] == b'\x7fELF'
    record['binary'] = {'path': str(binary), 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
(OUT / 'result.json').write_text(json.dumps(record, indent=2) + '\n')
print(json.dumps(record), flush=True)
raise SystemExit(rc != 0 or stopped is not None or bool(before) or bool(after))
