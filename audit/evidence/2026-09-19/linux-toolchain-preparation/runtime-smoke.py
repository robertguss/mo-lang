"""Lead trusted Linux runtime probe; never executes candidate-authored code."""
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import time

ROOT = Path(__file__).resolve().parents[4]
OUT = Path(__file__).resolve().parent / 'runtime-smoke-01'
OUT.mkdir(exist_ok=False)
REV = 'e3a01bbf613c1f130955b6e123d5987a4c559d18'
SHA = '4d14520aaf25403396e14501efbab2f5cd3d7f29bba4ad7c124155c06c806c72'
SOURCE = '/opt/mo-harness/source-' + REV
BINARY = Path('/var/folders/f8/ft7ygqg92pj8qh0rwplbw2x80000gn/T/mo-trusted-cross-e2a7hp23/toolchain/zig-out/bin/mo')
INSTALLED = '/opt/mo-harness/bin/mo-e3a01bb-aarch64-linux-musl'
PREFIX = ['orbctl', 'run', '-m', 'mo-executor-r01', '-u', 'root']
GUARD = ROOT / 'toolchain/bench/step36/guard.py'
UNIT = 'mo-linux-runtime-r01'


def run(name, seconds, args):
    command = ['python3', str(GUARD), str(seconds), '--', *map(str, args)]
    started = datetime.now().astimezone().isoformat()
    with (OUT / (name + '.stdout.txt')).open('w') as out, (OUT / (name + '.stderr.txt')).open('w') as err:
        p = subprocess.Popen(command, cwd=ROOT, stdout=out, stderr=err, start_new_session=True)
        try:
            rc = p.wait(timeout=seconds + 5)
        finally:
            rows = subprocess.check_output(['ps', '-axo', 'pid=,pgid=,command='], text=True).splitlines()
            left = [r.strip() for r in rows if len(r.split(None, 2)) == 3 and r.split(None, 2)[1] == str(p.pid)]
            if left:
                os.killpg(p.pid, signal.SIGKILL)
                p.wait(timeout=5)
                time.sleep(.2)
    record = dict(command=command, started=started, finished=datetime.now().astimezone().isoformat(), exit_code=rc, remaining_group=left)
    (OUT / (name + '.status.json')).write_text(json.dumps(record, indent=2) + '\n')
    print(json.dumps({'step': name, **record}), flush=True)
    if rc or left:
        raise RuntimeError(name + ' failed; raw evidence retained')


assert hashlib.sha256(BINARY.read_bytes()).hexdigest() == SHA
run('transfer-binary', 90, ['orbctl', 'push', '-m', 'mo-executor-r01', BINARY, 'mo-linux-prep/'])
guard_bytes = subprocess.check_output(['git', 'show', REV + ':toolchain/bench/step36/guard.py'], cwd=ROOT)
install = '''import hashlib,json,pathlib,sys
source,binary,want,guard= sys.argv[1:]
incoming=pathlib.Path('/home/mo/mo-linux-prep/mo');data=incoming.read_bytes()
assert hashlib.sha256(data).hexdigest()==want and data[:4]==b'\\x7fELF'
p=pathlib.Path(binary);p.parent.mkdir(exist_ok=True)
with p.open('xb') as f:f.write(data)
p.chmod(0o755)
g=pathlib.Path(source)/'toolchain/bench/step36/guard.py';g.parent.mkdir(parents=True,exist_ok=True)
assert not g.exists()
g.write_bytes(bytes.fromhex(guard))
print(json.dumps({'binary':str(p),'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'guard_sha256':hashlib.sha256(g.read_bytes()).hexdigest()}))
'''
run('install-identity', 30, PREFIX + ['python3', '-c', install, SOURCE, INSTALLED, SHA, guard_bytes.hex()])
probe = '''import hashlib,json,os,pathlib,signal,subprocess,time
root=pathlib.Path.cwd();mo=os.environ['MO_BIN'];guard=root/'toolchain/bench/step36/guard.py'
def hashes():
 return {str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for top in ['examples','toolchain/src'] for p in (root/top).rglob('*') if p.is_file() and (p.suffix in ['.mo','.zig'] or p.name=='.mo.ids')}
before=hashes();failed=False
cases=[('model-tests',[mo,'test','examples/programs/agent/model.mo']),('model-conformance',[mo,'check','examples/programs/agent/model.mo']),('generic-conformance',[mo,'check','--recipe','Recipes.ModelClient.ModelClient','examples/programs/agent/model.mo']),('driver-check',[mo,'check','examples/programs/agent/tests/terminal-auth/driver.mo']),('driver-build',[mo,'build','examples/programs/agent/tests/terminal-auth/driver.mo','-o','terminal-auth']),('http-interpreter',['python3','examples/programs/agent/tests/terminal-auth/run.py','interpreter']),('http-compiled',['python3','examples/programs/agent/tests/terminal-auth/run.py','compiled'])]
for name,args in cases:
 command=['python3',str(guard),'180','--',*args];t=time.monotonic()
 p=subprocess.Popen(command,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,start_new_session=True)
 try:out,err=p.communicate(timeout=185)
 except subprocess.TimeoutExpired:os.killpg(p.pid,signal.SIGKILL);out,err=p.communicate(timeout=5)
 rows=subprocess.check_output(['ps','-eo','pid=,pgid=,args='],text=True).splitlines()
 left=[r for r in rows if len(r.split(None,2))==3 and r.split(None,2)[1]==str(p.pid)]
 if left:os.killpg(p.pid,signal.SIGKILL)
 print(json.dumps({'check':name,'command':command,'exit_code':p.returncode,'seconds':time.monotonic()-t,'stdout':out,'stderr':err,'remaining_group':left}),flush=True)
 failed|=p.returncode!=0 or bool(left)
 if failed:break
after=hashes();same=before==after
print(json.dumps({'source_files':len(before),'source_bytes_unchanged':same,'changed':[p for p in set(before)|set(after) if before.get(p)!=after.get(p)]}),flush=True)
raise SystemExit(int(failed or not same))
'''
(OUT / 'remote-probe.py').write_text(probe)
try:
    run('linux-runtime', 650, PREFIX + ['systemd-run', '--wait', '--pipe', '--collect', '--unit=' + UNIT,
        '--working-directory=' + SOURCE, '--property=RuntimeMaxSec=600s', '--property=TimeoutStopSec=5s',
        '--property=KillMode=control-group', '--property=MemoryMax=1536M', '--property=CPUQuota=150%',
        '--property=TasksMax=128', '--property=PrivateNetwork=yes', '--property=NoNewPrivileges=yes',
        '--setenv=MO_BIN=' + INSTALLED, '--setenv=PATH=/opt/mo-harness/zig-aarch64-linux-0.16.0:/usr/bin:/bin',
        '--setenv=ZIG_GLOBAL_CACHE_DIR=/opt/mo-harness/zig-cache-runtime-r01', 'python3', '-c', probe])
finally:
    cleanup = '''import json,pathlib,subprocess,sys
unit=sys.argv[1]
loaded=subprocess.check_output(['systemctl','list-units','--all','--no-legend',unit+'*'],text=True).strip()
if loaded:subprocess.run(['systemctl','stop',unit+'.service'],check=True,timeout=15)
units=subprocess.check_output(['systemctl','list-units','--all','--no-legend',unit+'*'],text=True).strip()
cg=pathlib.Path('/sys/fs/cgroup/system.slice')/(unit+'.service')
print(json.dumps({'units_before_cleanup':loaded,'units_after_cleanup':units,'cgroup_exists':cg.exists()}))
assert not units and not cg.exists()
'''
    run('final-cleanup', 30, PREFIX + ['python3', '-c', cleanup, UNIT])
