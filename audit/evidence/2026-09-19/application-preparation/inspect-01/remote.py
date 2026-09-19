import hashlib,json,pathlib,subprocess

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
