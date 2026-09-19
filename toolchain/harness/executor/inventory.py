"""inventory.py OUTPUT [EVIDENCE...]: read-only proof that no run is left on mo-executor-r01.

Collects run names, workspace IDs and candidate cgroups from the JSON records
under each EVIDENCE directory, asks the machine what of them still exists
(directories, containers, units, mounts, cgroups, tasks under the two slices),
and records the Mac's own `docker ps` for comparison. Writes OUTPUT/inventory.json
and exits 1 if anything owned remains. Changes nothing on either host.
"""
import json
from pathlib import Path
import re
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from adapter import LOAD, remote

HEX = '[0-9a-f]{32}'
CGROUP = re.compile(r'/sys/fs/cgroup/[A-Za-z0-9_./-]+/docker-[0-9a-f]{64}\.scope')
MACHINE = LOAD + '''import pathlib,subprocess
def run(*args):
 q=subprocess.run(args,capture_output=True,text=True,timeout=5); return {'exit':q.returncode,'stdout':q.stdout,'stderr':q.stderr}
r={'containers':run('docker','ps','-a','--no-trunc','--format','{{.ID}} {{.Names}} {{.State}}'),
   'units':run('systemctl','list-units','--all','--no-legend','mo-executor-*','mo-appv1-*'),
   'mounts':run('findmnt','--json','-o','TARGET')}
paths=['/tmp/mo-executor-'+i for i in p['runs']]+['/var/lib/mo-harness/mo-workspace-'+i for i in p['workspaces']]+p['cgroups']
r['remaining_paths']=[x for x in paths if pathlib.Path(x).exists()]
r['slice_tasks']={str(f):f.read_text() for s in ('mo-executor.slice','mo-application.slice')
                  for f in pathlib.Path('/sys/fs/cgroup/mo.slice',s).rglob('cgroup.procs') if f.read_text().strip()}
print(json.dumps(r))
'''


def collect(roots):
    runs, workspaces, cgroups = set(), set(), set()
    def visit(value):
        if isinstance(value, dict):
            for key, item in value.items():
                if key == 'workspace_id' and isinstance(item, str) and re.fullmatch(HEX, item): workspaces.add(item)
                if key == 'execution_id' and isinstance(item, str) and re.fullmatch(HEX, item): runs.add(item)
                if key == 'name' and isinstance(item, str) and re.fullmatch('mo-executor-' + HEX, item): runs.add(item[12:])
                visit(item)
        elif isinstance(value, list):
            for item in value: visit(item)
        elif isinstance(value, str) and CGROUP.fullmatch(value):
            cgroups.add(value)
    for root in roots:
        for path in Path(root).rglob('*.json'):
            try: visit(json.loads(path.read_text()))
            except (ValueError, UnicodeError, OSError): pass
    return {'runs': sorted(runs), 'workspaces': sorted(workspaces), 'cgroups': sorted(cgroups)}


def main(output, roots):
    output = Path(output); output.mkdir(parents=True, exist_ok=False)
    selection = collect(roots)
    machine = json.loads(remote(['python3', '-c', MACHINE], data=json.dumps({**selection, 'sources': {}}).encode(), timeout=60))
    shared = subprocess.run(['docker', 'ps', '-a', '--no-trunc', '--format', '{{.ID}} {{.State}}'], capture_output=True, text=True, timeout=15)
    owned = sorted(set(selection['runs']) | set(selection['workspaces']))
    clean = (not machine['remaining_paths'] and not machine['slice_tasks'] and
             all(machine[k]['exit'] == 0 and not machine[k]['stdout'].strip() for k in ('containers', 'units')) and
             not any(i in machine['mounts']['stdout'] for i in owned))
    record = {'selection': selection, 'machine': machine, 'clean': clean,
              'shared_mac': {'exit': shared.returncode, 'stdout': shared.stdout, 'stderr': shared.stderr}}
    (output / 'inventory.json').write_text(json.dumps(record, indent=2) + '\n')
    print(json.dumps({'runs': len(selection['runs']), 'workspaces': len(selection['workspaces']),
                      'cgroups': len(selection['cgroups']), 'clean': clean}), flush=True)
    return 0 if clean else 1


if __name__ == '__main__':
    sys.exit(main(sys.argv[1], sys.argv[2:]))
