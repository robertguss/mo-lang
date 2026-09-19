"""Read-only absence and unchanged-policy proof for this lead attempt's IDs."""
import json
from pathlib import Path
import re
import subprocess
import sys

root = Path(sys.argv[1])
readiness = sys.argv[2:] == ['--readiness']
assert not sys.argv[2:] or readiness
prefix = 'readiness' if readiness else 'final'
runs, workspaces, cgroups = set(), set(), set()


def visit(value):
    if isinstance(value, dict):
        wid, eid, name = value.get('workspace_id'), value.get('execution_id'), value.get('name')
        if isinstance(wid, str) and re.fullmatch('[0-9a-f]{32}', wid):
            workspaces.add(wid)
        if isinstance(eid, str) and re.fullmatch('[0-9a-f]{32}', eid):
            runs.add('mo-executor-' + eid)
        if isinstance(name, str) and re.fullmatch('mo-executor-[0-9a-f]{32}', name):
            runs.add(name)
        for item in value.values():
            visit(item)
    elif isinstance(value, list):
        for item in value:
            visit(item)
    elif isinstance(value, str) and re.fullmatch('/sys/fs/cgroup/[A-Za-z0-9_./-]+/docker-[0-9a-f]{64}.scope', value):
        cgroups.add(value)


for path in root.rglob('*.json'):
    if path.name in ('source-before.json', 'source-after.json'):
        continue
    try:
        visit(json.loads(path.read_text()))
    except (ValueError, UnicodeError):
        continue
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
r['active']={}
for name in r['parents']:
 q=subprocess.run(['systemctl','is-active',name],capture_output=True,text=True,timeout=5)
 r['active'][name]={'exit':q.returncode,'stdout':q.stdout,'stderr':q.stderr}
r['images']={}
for image in ('sha256:debdba9954b1065ab1ce723c6c1f2f22e52a78c164f863b938d58cc2c9f0d337','sha256:b9fda4ae85f369e475e0f412e15dea9044a849a64bc2ec94bb3bc5a661eab3c4'):
 q=subprocess.run(['docker','image','inspect','--format','{{.Id}}',image],capture_output=True,text=True,timeout=5)
 r['images'][image]={'exit':q.returncode,'stdout':q.stdout,'stderr':q.stderr}
r['manifest_sha256']=hashlib.sha256(pathlib.Path('/opt/mo-harness/application-build-v1/package-02/package/manifest.json').read_bytes()).hexdigest()
print(json.dumps(r))
'''
argv = ['orbctl', 'run', '-m', 'mo-executor-r01', '-u', 'root', 'python3', '-B', '-c', source]
p = subprocess.run(argv, input=json.dumps(payload).encode(), capture_output=True, timeout=40)
(root / (prefix + '-command.json')).write_text(json.dumps({'argv': argv, 'input': payload, 'exit': p.returncode,
    'stderr': p.stderr.decode(errors='replace')}, indent=2))
p.check_returncode()
result = json.loads(p.stdout)
(root / (prefix + '-inventory.json')).write_text(json.dumps(result, indent=2))
assert readiness or (runs and workspaces)
assert not result['remaining_paths'] and not result['owned_processes']
assert all(result[k]['exit'] == 0 for k in ('containers', 'units', 'mounts', 'processes'))
assert not any(name in result['containers']['stdout'] or name in result['units']['stdout'] for name in runs)
assert not any(wid in result['mounts']['stdout'] for wid in workspaces)
assert all(not v['tasks'] for v in result['parents'].values())
for name, memory, pids in [('mo-application.slice', 1610612736, 192), ('mo-executor.slice', 536870912, 128)]:
    values = result['parents'][name]
    assert int(values['memory.max']) == memory and int(values['pids.max']) == pids
    assert int(values['memory.swap.max']) == 0 and values['cpu.max'].strip() == '100000 100000'
assert result['slice_sha256']['mo-application.slice'] == 'ab7ea2ac24e3248cc436348ea11251db3d650c160bf443907b16bda6e1e00702'
assert all(v['exit'] == 0 and v['stdout'].strip() == 'active' for v in result['active'].values())
assert all(v['exit'] == 0 and v['stdout'].strip() == image for image, v in result['images'].items())
assert result['manifest_sha256'] == 'd31b5c5e7e1912f98eba21268854d0f7b830dba7048b2de0e2c0458d10e507eb'
print(json.dumps({'runs': len(runs), 'workspaces': len(workspaces), 'actual_cgroups': len(cgroups),
    'cleanup': 'confirmed', 'parents_empty': True}))
