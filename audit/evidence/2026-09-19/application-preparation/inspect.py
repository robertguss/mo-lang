"""Lead read-only application machine readiness; no candidate dispatch."""
from pathlib import Path
import json, subprocess, signal, os, time
ROOT=Path(__file__).resolve().parents[4]
OUT=Path(__file__).with_name('inspect-01');OUT.mkdir()
code=r'''import hashlib,json,pathlib,subprocess

def run(*args):
 p=subprocess.run(args,capture_output=True,text=True,timeout=20)
 return {'command':args,'exit':p.returncode,'stdout':p.stdout,'stderr':p.stderr}
records=[run('free','-b'),run('df','-B1','/','/opt/mo-harness'),run('docker','ps','-a','--no-trunc','--format','{{json .}}'),run('docker','image','ls','--no-trunc','--format','{{json .}}'),run('systemctl','list-units','--all','--no-legend','mo-*'),run('systemctl','show','mo.slice','mo-executor.slice','mo-application.slice','-p','LoadState','-p','ActiveState','-p','ControlGroup','-p','MemoryMax','-p','MemorySwapMax','-p','CPUQuotaPerSecUSec','-p','TasksMax')]
for x in records:print(json.dumps(x))
for s in ['/etc/systemd/system/mo-executor.slice','/etc/systemd/system/mo-application.slice']:
 p=pathlib.Path(s);print(json.dumps({'path':s,'exists':p.exists(),'text':p.read_text() if p.exists() else None}))
for s in ['/sys/fs/cgroup/mo.slice','/sys/fs/cgroup/mo.slice/mo-executor.slice']:
 p=pathlib.Path(s);print(json.dumps({'cgroup':s,'values':{n:(p/n).read_text() for n in ['cgroup.procs','cgroup.subtree_control','memory.current','memory.max','memory.events','cpu.max','pids.current','pids.max'] if (p/n).exists()},'children':[x.name for x in p.iterdir() if x.is_dir()]}))
p=pathlib.Path('/opt/mo-harness/bin/mo-e3a01bb-aarch64-linux-musl');print(json.dumps({'compiler':str(p),'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'bytes':p.stat().st_size}))
print(json.dumps({'zig':run('/opt/mo-harness/zig-aarch64-linux-0.16.0/zig','version')}))
'''
cmd=['python3',str(ROOT/'toolchain/bench/step36/guard.py'),'90','--','orbctl','run','-m','mo-executor-r01','-u','root','python3','-c',code]
(OUT/'remote.py').write_text(code)
with (OUT/'stdout.jsonl').open('w') as out,(OUT/'stderr.txt').open('w') as err:
 p=subprocess.Popen(cmd,stdout=out,stderr=err,start_new_session=True)
 try:rc=p.wait(timeout=95)
 finally:
  try:os.killpg(p.pid,signal.SIGKILL)
  except ProcessLookupError:pass
  p.wait();time.sleep(.1)
try:os.killpg(p.pid,0);left=True
except ProcessLookupError:left=False
(OUT/'status.json').write_text(json.dumps({'command':cmd,'exit':rc,'group_remaining':left},indent=2)+'\n')
assert rc==0 and not left
print('application-readiness inspection complete',flush=True)
