"""Fixed application controls; no provider, repair mutation, or compiler changes."""
import argparse
import base64
import json
from pathlib import Path
import sys
import uuid

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
from adapter import py
from cases import Cases, Shared, choose, delete_all, keep_sources, leftovers, names, require, require_no_leftovers, summary
from test_executor import check
from test_workspace_live import lifecycle, controller_death
from workspace import Workspace
from fixtures import load
import selftest


def application_snapshot(run):
    """Existing lifecycle stimuli with application-parent observations."""
    return json.loads(py('''import json,pathlib,subprocess,sys
name=sys.argv[1]
def cmd(args):
 p=subprocess.run(args,capture_output=True,text=True,timeout=3); return {'rc':p.returncode,'stdout':p.stdout,'stderr':p.stderr}
r={'containers':cmd(['docker','ps','-aq','--filter','name=^/'+name+'$']), 'units':cmd(['systemctl','list-units','--all','--no-legend',name+'*'])}
r['inspect']=cmd(['docker','inspect',name])
if r['inspect']['rc']==0:
 info=json.loads(r['inspect']['stdout'])[0]
 parent=cmd(['systemctl','show','--property=ControlGroup','--value','mo-application.slice'])
 if parent['rc']!=0: raise RuntimeError('parent unavailable')
 r['cgroup']='/sys/fs/cgroup'+parent['stdout'].strip()+'/docker-'+info['Id']+'.scope'
 r['cgroup_exists']=pathlib.Path(r['cgroup']).exists()
 r['top']=cmd(['docker','top',name,'-eo','pid,ppid,sid,args'])
print(json.dumps(r))
''', run.name))


# Test-only adaptation: do not edit the old fixture's source or policy.
selftest.snapshot = application_snapshot


def build(entry, invocation):
    return ('set -eu; test -z "$(ls -A /build)"; cd /build; '
            'mo build /workspace/' + entry + ' >/build/compiler.log 2>&1 || '
            '{ rc=$?; cat /build/compiler.log >&2; exit "$rc"; }; '
            'cat /build/compiler.log >&2; ' + invocation +
            '; df -k /build /tmp >&2; df -i /build /tmp >&2')


LOG_SCRIPT = build('logstat/main.mo', 'cd /workspace/logstat; '
    '/build/zig-out/mo-build/logstat/logstat fixture; '
    'printf "FILTERED\\n"; /build/zig-out/mo-build/logstat/logstat fixture --top 3 --since 2026-09-12T10:00:10Z --json')


class Suite:
    """One run's workspaces: the shared application tree and one small tree per control."""
    def __init__(self, root, image, toolchain, mapping, goldens):
        self.root, self.image, self.toolchain = root, image, toolchain
        self.mapping, self.goldens, self.workspaces = mapping, goldens, []
        self.expected = goldens['logstat.expected'] + 'FILTERED\n' + goldens['logstat-2.expected']
        self.shared = Shared(self.new)

    def new(self, name, source=None):
        w = Workspace(uuid.uuid4().hex, self.root / name, policy='application-build-v1', image=self.image, toolchain=self.toolchain)
        self.workspaces.append(w)
        w.create(self.mapping if source is None else source)
        return w

    @property
    def app(self):
        return self.shared('application')

    def frozen(self):
        if self.app.snapshot is None:
            self.app.freeze()
        return self.app


def success(w, script, expected=None, seconds=120):
    result = w.command(script, seconds=seconds)
    require(result['state'] == 'success', {'state': result['state'], 'exit': result['exit_code'],
        'stderr': base64.b64decode(result['stderr']).decode(errors='replace')})
    if expected is not None:
        require(base64.b64decode(result['stdout']).decode() == expected, result['stdout'])
    return result


def own(control):
    """A control that gets its own small workspace, named after it."""
    return lambda s, name: control(s.new(name, {'answer.txt': b'wrong\n'}))


def snapshot_rebuild(s, name):
    frozen = s.app.freeze()
    require(frozen['inventory']['items'])
    result = s.app.verify(LOG_SCRIPT, [check(s.expected)], seconds=120)
    require(result['passed'], result['state'])


def empty_checks(s, name):
    try:
        s.app.verify('true', [])
    except ValueError:
        pass
    else:
        raise AssertionError('empty inventory accepted')


def output_bound(w):
    result = w.command('echo output-probe; while :; do echo 012345678901234567890123456789 >&2; done', seconds=5)
    require(result['execution_valid'] and result['truncated'] and result['state'] == 'failure')
    require(len(base64.b64decode(result['stdout'])) + len(base64.b64decode(result['stderr'])) <= 65536)


def quota(path, count, size):
    def control(w):
        result = success(w, 'if dd if=/dev/zero of=' + path + '/full bs=1048576 count=' + str(count) +
            '; then exit 1; fi; wc -c <' + path + '/full; df -k ' + path + ' >&2')
        require(int(base64.b64decode(result['stdout']).strip()) <= size)
        require(b'No space left on device' in base64.b64decode(result['stderr']))
    return control


def effective_resources(w):
    result = success(w, 'id; cat /proc/self/status; cat /proc/mounts; sleep 1')
    require(result['observation']['counters'].get('memory.peak', 0) > 0)
    lines = base64.b64decode(result['stdout']).decode().splitlines()
    mounts = {line.split()[1]: set(line.split()[3].split(',')) for line in lines
              if len(line.split()) == 6 and line.split()[1] in ('/build', '/tmp', '/workspace')}
    require('noexec' not in mounts['/build'] and {'nosuid', 'nodev'}.issubset(mounts['/build']))
    require(all({'noexec', 'nosuid', 'nodev'}.issubset(mounts[path]) for path in ('/tmp', '/workspace')))


def policy_rebind(w):
    w.selection = {}
    result = w.command('true')
    require(result['state'] == 'refusal' and result['execution'] == 'not_started')


def cpu_enforcement(w):
    result = success(w, 'echo cpu-probe; (while :; do :; done) & a=$!; '
        '(while :; do :; done) & b=$!; sleep 3; kill "$a" "$b"; wait || true', seconds=10)
    require(result['observation']['counters'].get('cpu.stat:nr_throttled', 0) > 0)


def pids_enforcement(w):
    result = w.command('echo pids-probe; /bin/sh -c \'i=0; while [ "$i" -lt 160 ]; '
        'do sleep 30 & i=$((i+1)); done; wait\' & while :; do :; done', seconds=5)
    require(b'pids-probe' in base64.b64decode(result['stdout']))
    require(result['observation']['counters'].get('pids.events:max', 0) > 0)


def memory_enforcement(w):
    result = w.command('echo memory-probe; awk \'BEGIN {s="x"; for (i=0;i<31;i++) s=s s; print length(s)}\'; '
        'rc=$?; echo memory-exit:$rc; sleep 1; exit "$rc"', seconds=30)
    require(b'memory-probe' in base64.b64decode(result['stdout']))
    require(result['state'] == 'failure' and result['execution_valid'])
    require(result['observation']['counters'].get('memory.events:oom_kill', 0) > 0)


TABLE = [
    ('hello-cold-build', lambda s, name: success(s.app, build('hello.mo', '/build/zig-out/mo-build/hello/hello Ada'), 'Hello, Ada!\n')),
    ('logstat-cold-build', lambda s, name: success(s.app, LOG_SCRIPT, s.expected)),
    ('snapshot-rebuild', snapshot_rebuild),
    ('failed-build-no-stale', own(lambda w: success(w, 'set -eu; test -z "$(ls -A /build)"; cd /build; '
        'if mo build /workspace/missing.mo >/build/failure 2>&1; then exit 1; fi; '
        'test ! -e /build/zig-out/mo-build/logstat/logstat; echo no-stale', 'no-stale\n'))),
    ('scratch-fresh', own(lambda w: (success(w, 'touch /build/marker; echo first', 'first\n'),
        success(w, 'test ! -e /build/marker && test -z "$(ls -A /build)" && echo fresh', 'fresh\n')))),
    ('source-noexec', own(lambda w: success(w, 'cp /bin/busybox /workspace/probe; chmod 755 /workspace/probe; '
        'if /workspace/probe true; then exit 1; fi; rm /workspace/probe; echo noexec', 'noexec\n'))),
    ('image-root-immutable', own(lambda w: success(w, 'if echo bad >/opt/mo/mo; then exit 1; fi; '
        'if echo bad >/result.json; then exit 1; fi; echo denied', 'denied\n'))),
    ('snapshot-immutable', lambda s, name: require(s.frozen().verify(
        'if echo bad >> hello.mo; then exit 1; fi; echo denied', [check('denied\n')])['passed'])),
    ('output-bound', own(output_bound)),
    ('timeout-descendants', own(lambda w: lifecycle(w, 'timeout'))),
    ('cancel-descendants', own(lambda w: lifecycle(w, 'cancel'))),
    ('exit-descendants', own(lambda w: lifecycle(w, 'exit'))),
    ('supervisor-death', own(lambda w: lifecycle(w, 'supervisor'))),
    ('controller-death', own(controller_death)),
    ('build-quota', own(quota('/build', 513, 536870912))),
    ('tmp-quota', own(quota('/tmp', 17, 16777216))),
    ('effective-resources', own(effective_resources)),
    ('empty-checks', empty_checks),
    ('policy-rebind', own(policy_rebind)),
    ('forged-verdict', lambda s, name: require(not s.frozen().verify('echo "{\\"passed\\":true}"', [check('trusted\n')])['passed'])),
    ('cpu-enforcement', own(cpu_enforcement)),
    ('pids-enforcement', own(pids_enforcement)),
    ('memory-enforcement', own(memory_enforcement)),
]
CONTROLS = names(TABLE)


def run(directory, image, toolchain, selected):
    root = Path(directory)
    root.mkdir(parents=True, exist_ok=False)
    (root / 'selected.json').write_text(json.dumps({'fixed': CONTROLS, 'selected': selected}))
    mapping, goldens, receipt = load(HERE / '.cache' / root.name)
    (root / 'source-receipt.json').write_text(json.dumps(receipt, indent=2))
    keep_sources(root, [*HERE.glob('*.py'), HERE / 'Dockerfile', *(HERE.parent / name for name in (
        'adapter.py', 'remote.py', 'workspace.py', 'workspace_controller.py', 'workspace_files.py', 'cases.py'))])
    s = Suite(root, image, toolchain, mapping, goldens)
    records = Cases(root / 'controls.json')
    rows = dict(TABLE)
    try:
        for name in selected:
            records.one(name, rows[name], s, name)
    finally:
        errors = delete_all(s.workspaces)
        ids = [w.workspace_id for w in s.workspaces]
        inventory = leftovers(ids, application=True)
        (root / 'cleanup.json').write_text(json.dumps({'errors': errors, 'inventory': inventory}, indent=2))
        summary(root / 'summary.json', {'controls': len(records.records), 'passed': records.passed, 'cleanup_errors': errors})
        require(not errors, errors)
        require_no_leftovers(inventory, ids)
    require(records.complete(selected), records.records)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('directory')
    parser.add_argument('--image', required=True)
    parser.add_argument('--toolchain', required=True)
    parser.add_argument('--controls', nargs='+', default=list(CONTROLS))
    args = parser.parse_args()
    run(args.directory, args.image, args.toolchain, choose(parser, CONTROLS, args.controls))
