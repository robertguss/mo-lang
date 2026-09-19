"""Install pinned Zig and build trusted Mo source in the dedicated Linux machine."""
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parents[4]
OUT = Path(__file__).resolve().parent / 'install-build-01'
OUT.mkdir(exist_ok=False)
MACHINE = 'mo-executor-r01'
ARCHIVE = Path('/private/tmp/mo-linux-toolchain-bcqwt2vz/zig-aarch64-linux-0.16.0.tar.xz')
DIGEST = 'ea4b09bfb22ec6f6c6ceac57ab63efb6b46e17ab08d21f69f3a48b38e1534f17'
REV = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
PREFIX = ['orbctl', 'run', '-m', MACHINE, '-u', 'root']
GUARD = ROOT / 'toolchain/bench/step36/guard.py'


def run(name, seconds, args):
    command = ['python3', str(GUARD), str(seconds), '--', *map(str, args)]
    started = datetime.now(ZoneInfo('America/New_York')).isoformat()
    with (OUT / (name + '.stdout.txt')).open('w') as out, (OUT / (name + '.stderr.txt')).open('w') as err:
        p = subprocess.Popen(command, cwd=ROOT, stdout=out, stderr=err, start_new_session=True)
        try:
            rc = p.wait(timeout=seconds + 10)
        except subprocess.TimeoutExpired:
            os.killpg(p.pid, signal.SIGKILL)
            rc = p.wait(timeout=3)
        rows = subprocess.check_output(['ps', '-axo', 'pid=,pgid=,command='], text=True).splitlines()
        left = [r.strip() for r in rows if len(r.split(None, 2)) == 3 and r.split(None, 2)[1] == str(p.pid)]
        if left:
            os.killpg(p.pid, signal.SIGKILL)
            time.sleep(1)
    record = dict(command=command, started_et=started,
                  finished_et=datetime.now(ZoneInfo('America/New_York')).isoformat(),
                  exit_code=rc, remaining_group=left)
    (OUT / (name + '.status.json')).write_text(json.dumps(record, indent=2) + '\n')
    print(json.dumps({'step': name, **record}), flush=True)
    if rc or left:
        raise RuntimeError(name + ' failed; evidence retained')


assert ARCHIVE.stat().st_size == 51211944
assert hashlib.sha256(ARCHIVE.read_bytes()).hexdigest() == DIGEST
local = Path(tempfile.mkdtemp(prefix='mo-linux-source-'))
source = local / ('mo-source-' + REV + '.tar')
paths = ['toolchain/src', 'toolchain/runtime', 'toolchain/testdata',
         'toolchain/build.zig', 'toolchain/build.zig.zon', 'toolchain/PRELUDE.md',
         'toolchain/bench/step37/peer.zig', 'toolchain/bench/step37/fuzz.zig',
         'toolchain/bench/step39/limbo.zig', 'examples', 'mo-wiki/spec/errors.md']
with source.open('wb') as output:
    subprocess.run(['git', 'archive', REV, *paths], cwd=ROOT, stdout=output, check=True, timeout=30)
source_digest = hashlib.sha256(source.read_bytes()).hexdigest()
manifest = dict(commit=REV, paths=paths, source_archive=str(source), source_bytes=source.stat().st_size,
                source_sha256=source_digest, zig_archive=str(ARCHIVE), zig_sha256=DIGEST,
                machine=MACHINE, trusted_build=True, candidate_execution=False)
(OUT / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
run('transfer-directory', 30, ['orbctl', 'run', '-m', MACHINE, '-u', 'mo', 'mkdir', '-p', '/home/mo/mo-linux-prep'])
run('transfer-zig', 120, ['orbctl', 'push', '-m', MACHINE, ARCHIVE, 'mo-linux-prep/'])
run('transfer-source', 120, ['orbctl', 'push', '-m', MACHINE, source, 'mo-linux-prep/'])
install = """import hashlib,json,pathlib,tarfile,sys
rev,zig_hash,source_name,source_hash=sys.argv[1:]
base=pathlib.Path('/opt/mo-harness');base.mkdir(exist_ok=True)
incoming=pathlib.Path('/home/mo/mo-linux-prep')
for name,digest,dest in [('zig-aarch64-linux-0.16.0.tar.xz',zig_hash,base), (source_name,source_hash,base/('source-'+rev))]:
 data=incoming/name
 assert hashlib.sha256(data.read_bytes()).hexdigest()==digest
 if dest!=base: dest.mkdir(exist_ok=False)
 with tarfile.open(data) as tar: tar.extractall(dest,filter='data')
print(json.dumps({'zig':str(base/'zig-aarch64-linux-0.16.0'),'source':str(base/('source-'+rev))}))
"""
run('install', 120, PREFIX + ['python3', '-c', install, REV, DIGEST, source.name, source_digest])
zig = '/opt/mo-harness/zig-aarch64-linux-0.16.0/zig'
run('version', 30, PREFIX + [zig, 'version'])
service = 'mo-toolchain-build-r01'
directory = '/opt/mo-harness/source-' + REV + '/toolchain'
try:
    run('build', 950, PREFIX + ['systemd-run', '--wait', '--pipe', '--collect', '--unit=' + service,
        '--working-directory=' + directory, '--property=RuntimeMaxSec=900s', '--property=TimeoutStopSec=5s',
        '--property=KillMode=control-group', '--property=MemoryMax=1536M', '--property=CPUQuota=150%',
        '--property=TasksMax=128', '--property=PrivateNetwork=yes', '--property=NoNewPrivileges=yes',
        '--setenv=ZIG_GLOBAL_CACHE_DIR=/opt/mo-harness/zig-cache', zig, 'build', '-j2'])
finally:
    run('stop-owned-build', 30, PREFIX + ['systemctl', 'stop', service + '.service'])
    run('build-unit-state', 30, PREFIX + ['systemctl', 'list-units', '--all', '--no-legend', service + '*'])
run('binary-identity', 30, PREFIX + ['python3', '-c',
    "import hashlib,json,pathlib,sys;p=pathlib.Path(sys.argv[1]);print(json.dumps({'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'magic':p.read_bytes()[:4].hex()}))", directory + '/zig-out/bin/mo'])
