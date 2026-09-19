"""Read-only final inventory of exactly this lead attempt's allocations."""
import json
from pathlib import Path
import subprocess
import sys

root = Path(sys.argv[1])
runs, workspaces, cgroups = set(), set(), set()
for path in root.rglob('manifest.json'):
    item = json.loads(path.read_text())
    if 'run_id' in item and 'name' in item:
        runs.add(item['name'])
        if item.get('workspace', {}).get('workspace_id'):
            workspaces.add(item['workspace']['workspace_id'])
for path in root.rglob('request.json'):
    item = json.loads(path.read_text())
    if item.get('workspace_id'):
        workspaces.add(item['workspace_id'])
for path in root.rglob('result.json'):
    group = json.loads(path.read_text()).get('observation', {}).get('cgroup')
    if group:
        cgroups.add(group)
payload = {'runs': sorted(runs), 'workspaces': sorted(workspaces), 'cgroups': sorted(cgroups)}
source = '''import hashlib,json,pathlib,subprocess,sys
p=json.load(sys.stdin)
paths=['/tmp/'+v for v in p['runs']]+['/var/lib/mo-harness/mo-workspace-'+v for v in p['workspaces']]+p['cgroups']
r={'remaining_paths':[v for v in paths if pathlib.Path(v).exists()]}
for k,args in {'containers':['docker','ps','-a','--no-trunc','--format','{{.ID}} {{.Names}}'], 'units':['systemctl','list-units','--all','--no-legend','mo-executor-*','mo-appv1-*'], 'mounts':['findmnt','--json','-o','TARGET'], 'processes':['ps','-eo','pid,ppid,args']}.items():
 q=subprocess.run(args,capture_output=True,text=True,timeout=5);r[k]={'exit':q.returncode,'stdout':q.stdout,'stderr':q.stderr}
r['owned_processes']=[v for v in r['processes']['stdout'].splitlines() if any('/tmp/'+n+'/' in v for n in p['runs'])]
r['parents']={}
for name in ('mo-application.slice','mo-executor.slice'):
 d=pathlib.Path('/sys/fs/cgroup/mo.slice')/name
 r['parents'][name]={f:(d/f).read_text() for f in ('memory.max','memory.swap.max','cpu.max','pids.max')}
 r['parents'][name]['tasks']={str(f):f.read_text() for f in d.rglob('cgroup.procs') if f.read_text().strip()}
r['slice_sha256']={n:hashlib.sha256(pathlib.Path('/etc/systemd/system/'+n).read_bytes()).hexdigest() for n in r['parents']}
print(json.dumps(r))
'''
argv = ['orbctl', 'run', '-m', 'mo-executor-r01', '-u', 'root', 'python3', '-B', '-c', source]
p = subprocess.run(argv, input=json.dumps(payload).encode(), capture_output=True, timeout=40)
(root / 'final-command.json').write_text(json.dumps({'argv': argv, 'input': payload, 'exit': p.returncode, 'stderr': p.stderr.decode()}, indent=2))
p.check_returncode()
result = json.loads(p.stdout)
(root / 'final-inventory.json').write_text(json.dumps(result, indent=2))
assert runs and workspaces
assert not result['remaining_paths'] and not result['owned_processes']
assert all(result[k]['exit'] == 0 and not result[k]['stdout'].strip() for k in ('containers', 'units'))
assert result['mounts']['exit'] == 0 and not any(v in result['mounts']['stdout'] for v in workspaces)
assert all(not v['tasks'] for v in result['parents'].values())
for name, memory, pids in [('mo-application.slice', 1610612736, 192), ('mo-executor.slice', 536870912, 128)]:
    values = result['parents'][name]
    assert int(values['memory.max']) == memory and int(values['pids.max']) == pids
    assert int(values['memory.swap.max']) == 0 and values['cpu.max'].strip() == '100000 100000'
assert result['slice_sha256']['mo-application.slice'] == 'ab7ea2ac24e3248cc436348ea11251db3d650c160bf443907b16bda6e1e00702'
print(json.dumps({'runs': len(runs), 'workspaces': len(workspaces), 'cleanup': 'confirmed', 'parents_empty': True}))
