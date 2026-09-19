"""One runner for the live suites; nothing here runs at import.

Each live suite is a table of (name, action) rows plus the few helpers that are
its own. This module holds what they share: selection from the fixed table, one
record per case (written and printed as each ends), the summary line, the Mac's
own Docker baseline, and the machine-side proofs that nothing owned is left.
"""
from contextlib import contextmanager
import json
from pathlib import Path
import shutil
import subprocess
import time
import traceback

from adapter import py

# The released application-build-v1 image and toolchain package.
APPLICATION_IMAGE = 'sha256:b9fda4ae85f369e475e0f412e15dea9044a849a64bc2ec94bb3bc5a661eab3c4'
APPLICATION_TOOLCHAIN = 'd31b5c5e7e1912f98eba21268854d0f7b830dba7048b2de0e2c0458d10e507eb'


def require(value, detail=None):
    if not value:
        raise AssertionError(detail)


def names(table):
    return tuple(name for name, _ in table)


def choose(parser, fixed, selected):
    """The selection in its given order; argparse exits 2 before anything is created."""
    if not selected or len(set(selected)) != len(selected) or set(selected) - set(fixed):
        parser.error('unknown, empty or duplicate selection')
    return list(selected)


class Cases:
    """Runs table rows in order. Each row leaves one record, {key: name, 'ok',
    'elapsed_seconds', 'error' (the traceback) if it failed, and any fields the
    action returns}, rewritten to `path` and printed as a JSON line."""

    def __init__(self, path, *, key='case', stop=False):
        self.path, self.key, self.stop = Path(path), key, stop
        self.records = []

    def run(self, table, selected, *args, after=None):
        rows = dict(table)
        for name in selected:
            if not self.one(name, rows[name], *args, after=after)['ok'] and self.stop:
                break
        return self.records

    def one(self, name, action, *args, after=None):
        record = {self.key: name, 'ok': False}
        started = time.monotonic()
        try:
            record.update(action(*args) or {})
            if after:
                after()
            record['ok'] = True
        except Exception:
            record['error'] = traceback.format_exc()
        record['elapsed_seconds'] = round(time.monotonic() - started, 3)
        self.records.append(record)
        self.path.write_text(json.dumps(self.records, indent=2))
        print(json.dumps(record), flush=True)
        return record

    @property
    def passed(self):
        return sum(record['ok'] for record in self.records)

    def complete(self, selected):
        return len(self.records) == len(selected) and self.passed == len(selected)


@contextmanager
def then(cleanup):
    """Runs `cleanup` after the body however it ends. When both fail, the body's
    failure is the one raised, carrying the cleanup's traceback as a note."""
    try:
        yield
    except BaseException as failure:
        try:
            cleanup()
        except Exception:
            failure.add_note('cleanup also failed:\n' + traceback.format_exc())
        raise
    cleanup()


class Shared:
    """Workspaces that several cases use, made on first use. A failed creation is
    kept, so the later cases report it instead of retrying into a used directory."""
    def __init__(self, make):
        self.make, self.made = make, {}

    def __call__(self, name):
        if name not in self.made:
            try:
                self.made[name] = self.make(name)
            except Exception as exc:
                self.made[name] = exc
                raise
        if isinstance(self.made[name], Exception):
            raise RuntimeError(f'shared workspace {name!r} was not created') from self.made[name]
        return self.made[name]


def summary(path, value, indent=None):
    Path(path).write_text(json.dumps(value, indent=2))
    print(json.dumps(value, indent=indent), flush=True)


def keep_sources(root, paths):
    """Copies of the exact files a run used, beside its evidence."""
    (root / 'sources').mkdir(exist_ok=True)
    for path in paths:
        shutil.copyfile(path, root / 'sources' / Path(path).name)


def until(check, seconds, message, interval=.1):
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        value = check()
        if value:
            return value
        time.sleep(interval)
    raise AssertionError(message)


def resume(directory, kind=None):
    """A run object for an existing run directory, for a child that outlives its controller."""
    if kind is None:
        from adapter import Run as kind
    run = kind.__new__(kind)
    run.directory = Path(directory)
    run.manifest = json.loads((run.directory / 'manifest.json').read_text())
    run.name = run.manifest['name']
    run.root = '/tmp/' + run.name
    return run


def registration(name):
    """The candidate's registration record once it is registered and its
    container is running on the machine; None before then."""
    return json.loads(py('''import json,pathlib,subprocess,sys
name=sys.argv[1]; path=pathlib.Path('/tmp',name,'registration.json')
p=subprocess.run(['docker','inspect',name],capture_output=True,timeout=5)
running=p.returncode==0 and json.loads(p.stdout)[0]['State']['Running']
print(json.dumps(json.loads(path.read_text()) if running and path.exists() else None))
''', name))


def mac_docker():
    """The Mac's own containers. Every suite must leave them as it found them."""
    return subprocess.run(['docker', 'ps', '-a', '--no-trunc', '--format', '{{.ID}} {{.State}}'],
                          capture_output=True, check=True, timeout=10).stdout


def workspace_absence(receipts):
    """For each ownership receipt: its workspace root and mounts, and for each
    recorded execution its root, container, units and cgroup, as the machine sees them."""
    return json.loads(py('''import json,pathlib,subprocess,sys
rows=json.load(sys.stdin); result=[]
def cmd(argv):
 p=subprocess.run(argv,capture_output=True,text=True,timeout=5)
 if p.returncode: raise RuntimeError((argv,p.returncode,p.stderr))
 return p.stdout
mounts=pathlib.Path('/proc/self/mountinfo').read_text()
for r in rows:
 root='/var/lib/mo-harness/mo-workspace-'+r['workspace_id']
 item={'workspace_id':r['workspace_id'],'root_exists':pathlib.Path(root).exists(),'mounts':[l for l in mounts.splitlines() if root in l],'executions':[]}
 terminal=pathlib.Path('/var/lib/mo-harness/.recovery-'+r['workspace_id'])
 saved=json.loads(terminal.read_text()) if terminal.exists() else {}
 for e in r['executions']:
  name='mo-executor-'+e['execution_id'];proof=saved.get('executions',{}).get(e['execution_id'],{})
  cg=proof.get('host_cgroup')
  item['executions'].append({'id':e['execution_id'],'root_exists':pathlib.Path('/tmp/'+name).exists(),'containers':cmd(['docker','ps','-aq','--no-trunc','--filter','name=^/'+name+'$']),'units':cmd(['systemctl','list-units','--all','--no-legend',name+'*']),'cgroup':cg,'cgroup_exists':bool(cg and pathlib.Path(cg).exists())})
 result.append(item)
print(json.dumps(result))
''', data=json.dumps(receipts).encode()))


def require_absent(rows):
    require(all(not row['root_exists'] and not row['mounts'] and all(
        not e['root_exists'] and not e['containers'].strip() and not e['units'].strip() and not e['cgroup_exists']
        for e in row['executions']) for row in rows), rows)


def delete_all(workspaces):
    """Collects any active run, then deletes each workspace; returns the failures."""
    errors = []
    for w in workspaces:
        try:
            if w.active:
                w.collect()
            w.delete()
        except Exception:
            errors.append({'workspace_id': w.workspace_id, 'error': traceback.format_exc()})
    return errors


def leftovers(workspace_ids, application=False):
    """What the machine still holds: these workspaces' directories and mounts, and
    any executor container or unit (for application runs, any container at all
    and any task in the application slice)."""
    return json.loads(py('''import json,pathlib,subprocess,sys
ids=json.loads(sys.argv[1]); application=sys.argv[2]=='1'
r={'directories':[str(p) for i in ids if (p:=pathlib.Path('/var/lib/mo-harness/mo-workspace-'+i)).exists()]}
queries={'containers':['docker','ps','-aq']+([] if application else ['--filter','name=^/mo-executor-']),
 'units':['systemctl','list-units','--all','--no-legend','mo-executor-*'],'mounts':['findmnt','--json','-o','TARGET']}
if application: queries['application_tasks']=['cat','/sys/fs/cgroup/mo.slice/mo-application.slice/cgroup.procs']
for key,args in queries.items():
 p=subprocess.run(args,capture_output=True,text=True,timeout=3); r[key]={'exit':p.returncode,'stdout':p.stdout}
print(json.dumps(r))
''', json.dumps(list(workspace_ids)), '1' if application else '0'))


def require_no_leftovers(inventory, workspace_ids):
    require(not inventory['directories'], inventory)
    for key, value in inventory.items():
        if key not in ('directories', 'mounts'):
            require(value['exit'] == 0 and not value['stdout'].strip(), inventory)
    require(not any(i in inventory['mounts']['stdout'] for i in workspace_ids), inventory)
