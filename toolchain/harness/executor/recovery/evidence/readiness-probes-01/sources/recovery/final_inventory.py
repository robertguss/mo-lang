"""Read-only final proof for IDs retained in this worker's immutable attempts."""
import json
from pathlib import Path
import re
import subprocess
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from adapter import remote

base = Path(sys.argv[1])
output = Path(sys.argv[2])
output.mkdir(parents=True,exist_ok=False)
workspaces, executions, cgroups, groups = set(), set(), set(), set()
for path in base.rglob('*.json'):
    if 'sources' in path.parts:
        continue
    try:
        value = json.loads(path.read_text())
    except (ValueError,UnicodeError):
        continue
    if path.name in ('exit.json', 'owner-exit.json'):
        group = value.get('group', value.get('pid')) if isinstance(value, dict) else None
        if type(group) is int and group > 0:
            groups.add(group)
    def visit(value):
        if isinstance(value,dict):
            wid = value.get('workspace_id')
            if isinstance(wid,str) and re.fullmatch('[0-9a-f]{32}',wid):
                workspaces.add(wid)
            eid = value.get('execution_id')
            if isinstance(eid,str) and re.fullmatch('[0-9a-f]{32}',eid):
                executions.add(eid)
            name = value.get('name')
            if isinstance(name,str) and re.fullmatch('mo-executor-[0-9a-f]{32}',name):
                executions.add(name.removeprefix('mo-executor-'))
            for item in value.values(): visit(item)
        elif isinstance(value,list):
            for item in value: visit(item)
        elif isinstance(value,str) and re.fullmatch('/sys/fs/cgroup/[A-Za-z0-9_./-]+/docker-[0-9a-f]{64}.scope',value):
            cgroups.add(value)
    visit(value)
history = {path.name:sum(item.lstat().st_size for item in path.rglob('*') if item.is_file()) for path in base.iterdir() if path.is_dir()}
local = subprocess.check_output(['ps','-axo','pid=,pgid=,stat=,command='])
remaining = [line.decode() for line in local.splitlines() if len(line.split(None,3)) >= 3 and int(line.split(None,3)[1]) in groups]
(output/'local-processes.txt').write_bytes(local)
(output/'history.json').write_text(json.dumps({'groups':sorted(groups),'remaining':remaining,'attempt_bytes':history},indent=2))
assert not remaining, remaining
assert all(size <= 16*1024*1024 for size in history.values()), history
selection={'workspaces':sorted(workspaces),'executions':sorted(executions),'cgroups':sorted(cgroups)}
(output/'selection.json').write_text(json.dumps(selection,indent=2))
source='''import json,pathlib,subprocess,sys
p=json.load(sys.stdin)
def cmd(args):
 r=subprocess.run(args,capture_output=True,text=True,timeout=5)
 if r.returncode:raise RuntimeError((args,r.returncode,r.stderr))
 return r.stdout
containers=cmd(['docker','ps','-a','--no-trunc','--format','{{json .}}'])
units=cmd(['systemctl','list-units','--all','--no-legend','mo-executor-*'])
mounts=pathlib.Path('/proc/self/mountinfo').read_text().splitlines()
r={'containers':containers,'units':units,'workspaces':[],'executions':[],'cgroups':[], 'parents':{}}
for wid in p['workspaces']:
 root='/var/lib/mo-harness/mo-workspace-'+wid
 r['workspaces'].append({'id':wid,'root_exists':pathlib.Path(root).exists(),'mounts':[line for line in mounts if root in line]})
for eid in p['executions']:
 name='mo-executor-'+eid
 r['executions'].append({'id':eid,'root_exists':pathlib.Path('/tmp/'+name).exists(),'container_present':name in containers,'unit_present':name in units})
for group in p['cgroups']:r['cgroups'].append({'path':group,'exists':pathlib.Path(group).exists()})
for parent in ('mo-executor.slice','mo-application.slice'):
 group=cmd(['systemctl','show','--property=ControlGroup','--value',parent]).strip()
 root=pathlib.Path('/sys/fs/cgroup'+group)
 r['parents'][parent]={'group':group,'tasks':{str(path):path.read_text() for path in root.rglob('cgroup.procs')}}
print(json.dumps(r))
'''
raw=remote(['python3','-c',source],data=json.dumps(selection).encode(),timeout=60)
(output/'machine.json').write_bytes(raw)
r=json.loads(raw)
shared=subprocess.run(['docker','ps','-a','--no-trunc','--format','{{.ID}} {{.State}}'],capture_output=True,check=True,timeout=10).stdout
(output/'shared.txt').write_bytes(shared)
baselines=list(base.rglob('shared-before.txt'))
assert baselines
assert all(sorted(path.read_bytes().splitlines())==sorted(shared.splitlines()) for path in baselines)
assert len(shared.splitlines())==5
assert all(not row['root_exists'] and not row['mounts'] for row in r['workspaces'])
assert all(not any(row[k] for k in ('root_exists','container_present','unit_present')) for row in r['executions'])
assert all(not row['exists'] for row in r['cgroups'])
assert all(not text.strip() for parent in r['parents'].values() for text in parent['tasks'].values())
print(json.dumps({'workspaces':len(workspaces),'executions':len(executions),'actual_cgroups':len(cgroups),'shared':5,'local_groups':len(groups),'absent':True}))
