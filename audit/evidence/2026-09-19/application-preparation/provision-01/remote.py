import hashlib,json,pathlib,subprocess
cg=pathlib.Path('/sys/fs/cgroup')
outer={n:(cg/n).read_text().strip() for n in ['memory.max','memory.current','memory.swap.max','cpu.max','pids.max']}
print(json.dumps({'outer_machine_cgroup':outer,'self_cgroup':pathlib.Path('/proc/self/cgroup').read_text()}),flush=True)
assert outer['memory.max']=='2147483648' and outer['cpu.max']=='200000 100000'
assert not subprocess.check_output(['docker','ps','-aq'],text=True).strip()
old=pathlib.Path('/etc/systemd/system/mo-executor.slice');old_bytes=old.read_bytes()
oldcg=cg/'mo.slice/mo-executor.slice'
assert (oldcg/'memory.max').read_text().strip()=='536870912'
assert (oldcg/'pids.current').read_text().strip()=='0'
assert not [p for p in oldcg.iterdir() if p.is_dir()]
p=pathlib.Path('/etc/systemd/system/mo-application.slice')
config='[Unit]\nDescription=Bounded Mo application build trial\n[Slice]\nCPUQuota=100%\nMemoryMax=1536M\nMemorySwapMax=0\nTasksMax=192\n'
with p.open('x') as f:f.write(config)
p.chmod(0o644)
for cmd in [['systemctl','daemon-reload'],['systemctl','start','mo-application.slice']]:
 result=subprocess.run(cmd,capture_output=True,text=True,timeout=20)
 print(json.dumps({'command':cmd,'exit':result.returncode,'stdout':result.stdout,'stderr':result.stderr}),flush=True);result.check_returncode()
newcg=cg/'mo.slice/mo-application.slice'
values={n:(newcg/n).read_text().strip() for n in ['memory.max','memory.swap.max','cpu.max','pids.max','pids.current','cgroup.procs']}
assert values=={'memory.max':'1610612736','memory.swap.max':'0','cpu.max':'100000 100000','pids.max':'192','pids.current':'0','cgroup.procs':''},values
assert old.read_bytes()==old_bytes
print(json.dumps({'new_config':str(p),'config':config,'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'effective_cgroup':str(newcg),'values':values,'old_config_unchanged':True,'old_cgroup_memory_max':(oldcg/'memory.max').read_text().strip(),'containers':subprocess.check_output(['docker','ps','-aq'],text=True).strip()}),flush=True)
