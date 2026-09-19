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
OUT = Path(__file__).resolve().parent / 'build-02'
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


REV = json.loads((Path(__file__).resolve().parent / 'install-build-01/manifest.json').read_text())['commit']
PREFIX = ['orbctl', 'run', '-m', MACHINE, '-u', 'root']
zig = '/opt/mo-harness/zig-aarch64-linux-0.16.0/zig'
service = 'mo-toolchain-build-r02'
directory = '/opt/mo-harness/source-' + REV + '/toolchain'
try:
    run('build', 950, PREFIX + ['systemd-run', '--wait', '--pipe', '--collect', '--unit=' + service,
        '--working-directory=' + directory, '--property=RuntimeMaxSec=900s', '--property=TimeoutStopSec=5s',
        '--property=KillMode=control-group', '--property=MemoryMax=1536M', '--property=CPUQuota=150%',
        '--property=TasksMax=128', '--property=PrivateNetwork=yes', '--property=NoNewPrivileges=yes',
        '--setenv=ZIG_GLOBAL_CACHE_DIR=/opt/mo-harness/zig-cache', zig, 'build', '-j1'])
finally:
    run('final-state', 30, PREFIX + ['python3', '-c', "import json,subprocess;u=subprocess.run(['systemctl','list-units','--all','--no-legend','mo-toolchain-build-r0*'],capture_output=True,text=True,check=True);p=subprocess.run(['pgrep','-a','-x','zig'],capture_output=True,text=True);print(json.dumps({'units':u.stdout,'zig_processes':p.stdout,'pgrep_rc':p.returncode}));assert not u.stdout.strip() and p.returncode==1"])
run('binary-identity', 30, PREFIX + ['python3', '-c',
    "import hashlib,json,pathlib,sys;p=pathlib.Path(sys.argv[1]);print(json.dumps({'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'magic':p.read_bytes()[:4].hex()}))", directory + '/zig-out/bin/mo'])
