"""Read-only machine cleanup proof and exact allocation ledger for this worker."""
import json
from pathlib import Path
import shutil
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
PREFIX = ['orbctl', 'run', '-m', 'mo-executor-r01', '-u', 'root']


def main(directory):
    root = Path(directory)
    root.mkdir(parents=True, exist_ok=False)
    runs, workspaces, groups, builds = {}, set(), set(), []
    for path in sorted((HERE / 'evidence').rglob('manifest.json')):
        manifest = json.loads(path.read_text())
        if 'run_id' not in manifest or 'name' not in manifest:
            continue
        record = {'manifest': str(path.relative_to(HERE)), 'run_id': manifest['run_id'],
                  'name': manifest['name'], 'image': manifest['image'], 'policy': manifest['policy']}
        if manifest.get('workspace'):
            workspaces.add(manifest['workspace']['workspace_id'])
        result_path = path.with_name('result.json')
        if result_path.exists():
            result = json.loads(result_path.read_text())
            observation = result.get('observation', {})
            record.update(container_id=observation.get('container_id'), cleanup=observation.get('cleanup'),
                          exit_code=observation.get('exit_code'), status=observation.get('status'))
            if observation.get('cgroup'):
                groups.add(observation['cgroup'])
            if manifest['policy'] == 'application-build-v1':
                record['counters'] = observation.get('counters')
                record['elapsed_seconds'] = observation.get('elapsed_seconds')
                if '/application/execution-' in str(path):
                    builds.append(record)
        runs[manifest['name']] = record
    for path in (HERE / 'evidence').rglob('request.json'):
        request = json.loads(path.read_text())
        if 'workspace_id' in request:
            workspaces.add(request['workspace_id'])
    payload = {'runs': sorted(runs), 'workspaces': sorted(workspaces), 'cgroups': sorted(groups)}
    source = '''import hashlib,json,pathlib,subprocess,sys
p=json.load(sys.stdin); r={}
paths=['/tmp/'+name for name in p['runs']]+['/var/lib/mo-harness/mo-workspace-'+i for i in p['workspaces']]+p['cgroups']
r['remaining_owned_paths']=[path for path in paths if pathlib.Path(path).exists()]
for key,args in {'containers':['docker','ps','-a','--no-trunc','--format','{{.ID}} {{.Names}} {{.State}}'], 'units':['systemctl','list-units','--all','--no-legend','mo-executor-*','mo-appv1-*'], 'images':['docker','image','ls','-a','--no-trunc'], 'mounts':['findmnt','--json','-o','TARGET'], 'processes':['ps','-eo','pid,ppid,args']}.items():
 q=subprocess.run(args,capture_output=True,text=True,timeout=5); r[key]={'exit':q.returncode,'stdout':q.stdout,'stderr':q.stderr}
r['owned_processes']=[line for line in r['processes']['stdout'].splitlines() if any('/tmp/'+name+'/' in line for name in p['runs'])]
r['slice_files']={name:hashlib.sha256(pathlib.Path('/etc/systemd/system/'+name).read_bytes()).hexdigest() for name in ('mo-application.slice','mo-executor.slice')}
r['parents']={}
for name in ('mo-application.slice','mo-executor.slice'):
 path=pathlib.Path('/sys/fs/cgroup/mo.slice')/name
 r['parents'][name]={f:(path/f).read_text() for f in ('memory.max','memory.swap.max','memory.peak','memory.events','cpu.max','pids.max')}
 r['parents'][name]['tasks']={str(f):f.read_text() for f in path.rglob('cgroup.procs') if f.read_text().strip()}
print(json.dumps(r))
'''
    p = subprocess.run(PREFIX + ['python3', '-B', '-c', source], input=json.dumps(payload).encode(), capture_output=True, timeout=40)
    (root / 'machine-command.json').write_text(json.dumps({'argv': PREFIX + ['python3', '-B', '-c', source], 'input': payload}))
    (root / 'machine-exit.json').write_text(json.dumps({'exit': p.returncode, 'stderr': p.stderr.decode()}))
    p.check_returncode()
    machine = json.loads(p.stdout)
    (root / 'machine.json').write_text(json.dumps(machine, indent=2))
    (root / 'allocations.json').write_text(json.dumps(list(runs.values()), indent=2))
    (root / 'application-results.json').write_text(json.dumps(builds, indent=2))
    shared = subprocess.run(['docker', 'ps', '-a', '--no-trunc', '--format', '{{.ID}} {{.State}}'], capture_output=True, timeout=15)
    (root / 'shared-mac.json').write_text(json.dumps({'exit': shared.returncode, 'stdout': shared.stdout.decode(), 'stderr': shared.stderr.decode()}))
    before = json.loads((HERE / 'evidence/inspect-01/inventory/shared-mac.json').read_text())
    unchanged = shared.returncode == 0 and sorted(shared.stdout.decode().splitlines()) == sorted(before['stdout'].splitlines())
    cache = HERE / '.cache'
    cached_paths = [str(path.relative_to(HERE)) for path in cache.rglob('*')] if cache.exists() else []
    if cache.exists():
        shutil.rmtree(cache)
    proof = {'run_count': len(runs), 'workspace_count': len(workspaces), 'shared_mac_unchanged': unchanged,
             'local_cache_removed': cached_paths, 'local_cache_absent': not cache.exists()}
    (root / 'proof.json').write_text(json.dumps(proof, indent=2))
    assert not machine['remaining_owned_paths'], machine['remaining_owned_paths']
    assert not machine['owned_processes'], machine['owned_processes']
    for name in ('containers', 'units'):
        assert machine[name]['exit'] == 0 and not machine[name]['stdout'].strip(), machine[name]
    assert not any(identity in machine['mounts']['stdout'] for identity in workspaces)
    assert all(not parent['tasks'] for parent in machine['parents'].values())
    assert unchanged and not cache.exists(), proof
    print(json.dumps({'run_count': len(runs), 'workspace_count': len(workspaces), 'cleanup': 'confirmed', 'shared_mac_unchanged': unchanged}), flush=True)


if __name__ == '__main__':
    main(sys.argv[1])
