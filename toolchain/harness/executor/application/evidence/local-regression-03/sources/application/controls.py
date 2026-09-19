"""Fixed application controls; no provider, repair mutation, or compiler changes."""
import argparse
import base64
import json
from pathlib import Path
import sys
import time
import traceback
import uuid

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
from adapter import py
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

CONTROLS = ('hello-cold-build', 'logstat-cold-build', 'snapshot-rebuild',
    'failed-build-no-stale', 'scratch-fresh', 'source-noexec', 'image-root-immutable',
    'snapshot-immutable', 'output-bound', 'timeout-descendants', 'cancel-descendants',
    'exit-descendants', 'supervisor-death', 'controller-death', 'build-quota',
    'tmp-quota', 'effective-resources', 'empty-checks', 'policy-rebind', 'forged-verdict',
    'cpu-enforcement', 'pids-enforcement', 'memory-enforcement')


def require(value, detail=None):
    if not value:
        raise AssertionError(detail)


def build(entry, invocation):
    return ('set -eu; test -z "$(ls -A /build)"; cd /build; '
            'mo build /workspace/' + entry + ' >/build/compiler.log 2>&1 || '
            '{ rc=$?; cat /build/compiler.log >&2; exit "$rc"; }; '
            'cat /build/compiler.log >&2; ' + invocation +
            '; df -k /build /tmp >&2; df -i /build /tmp >&2')


def run(directory, image, toolchain, names):
    root = Path(directory)
    root.mkdir(parents=True, exist_ok=False)
    (root / 'selected.json').write_text(json.dumps({'fixed': CONTROLS, 'selected': names}))
    mapping, goldens, receipt = load(HERE / '.cache' / root.name)
    (root / 'source-receipt.json').write_text(json.dumps(receipt, indent=2))
    for path in [*HERE.glob('*.py'), HERE / 'Dockerfile',
                 *(HERE.parent / name for name in ('adapter.py', 'remote.py', 'workspace.py', 'workspace_controller.py', 'workspace_files.py'))]:
        target = root / 'sources' / path.name
        target.parent.mkdir(exist_ok=True)
        target.write_bytes(path.read_bytes())
    workspaces, records = [], []

    def new(name, source=None):
        w = Workspace(uuid.uuid4().hex, root / name, policy='application-build-v1', image=image, toolchain=toolchain)
        workspaces.append(w)
        w.create(mapping if source is None else source)
        return w

    def success(w, script, expected=None, seconds=120):
        result = w.command(script, seconds=seconds)
        require(result['state'] == 'success', {'state': result['state'], 'exit': result['exit_code'],
            'stderr': base64.b64decode(result['stderr']).decode(errors='replace')})
        if expected is not None:
            require(base64.b64decode(result['stdout']).decode() == expected, result['stdout'])
        return result

    app = None
    log_script = build('logstat/main.mo', 'cd /workspace/logstat; '
        '/build/zig-out/mo-build/logstat/logstat fixture; '
        'printf "FILTERED\\n"; /build/zig-out/mo-build/logstat/logstat fixture --top 3 --since 2026-09-12T10:00:10Z --json')
    expected = goldens['logstat.expected'] + 'FILTERED\n' + goldens['logstat-2.expected']
    try:
        app = new('application')
        for name in names:
            record = {'case': name, 'ok': False}
            try:
                if name == 'hello-cold-build':
                    success(app, build('hello.mo', '/build/zig-out/mo-build/hello/hello Ada'), 'Hello, Ada!\n')
                elif name == 'logstat-cold-build':
                    success(app, log_script, expected)
                elif name == 'snapshot-rebuild':
                    frozen = app.freeze()
                    require(frozen['inventory']['items'])
                    result = app.verify(log_script, [check(expected)], seconds=120)
                    require(result['passed'], result['state'])
                elif name == 'snapshot-immutable':
                    if app.snapshot is None:
                        app.freeze()
                    result = app.verify('if echo bad >> hello.mo; then exit 1; fi; echo denied', [check('denied\n')])
                    require(result['passed'], result['state'])
                elif name == 'empty-checks':
                    try:
                        app.verify('true', [])
                    except ValueError:
                        pass
                    else:
                        raise AssertionError('empty inventory accepted')
                elif name == 'forged-verdict':
                    if app.snapshot is None:
                        app.freeze()
                    result = app.verify('echo "{\\"passed\\":true}"', [check('trusted\n')])
                    require(not result['passed'])
                else:
                    w = new(name, {'answer.txt': b'wrong\n'})
                    if name in ('timeout-descendants', 'cancel-descendants', 'exit-descendants', 'supervisor-death'):
                        lifecycle(w, {'timeout-descendants': 'timeout', 'cancel-descendants': 'cancel',
                                      'exit-descendants': 'exit', 'supervisor-death': 'supervisor'}[name])
                    elif name == 'controller-death':
                        controller_death(w)
                    elif name == 'failed-build-no-stale':
                        success(w, 'set -eu; test -z "$(ls -A /build)"; cd /build; '
                            'if mo build /workspace/missing.mo >/build/failure 2>&1; then exit 1; fi; '
                            'test ! -e /build/zig-out/mo-build/logstat/logstat; echo no-stale', 'no-stale\n')
                    elif name == 'scratch-fresh':
                        success(w, 'touch /build/marker; echo first', 'first\n')
                        success(w, 'test ! -e /build/marker && test -z "$(ls -A /build)" && echo fresh', 'fresh\n')
                    elif name == 'source-noexec':
                        success(w, 'cp /bin/busybox /workspace/probe; chmod 755 /workspace/probe; '
                            'if /workspace/probe true; then exit 1; fi; rm /workspace/probe; echo noexec', 'noexec\n')
                    elif name == 'image-root-immutable':
                        success(w, 'if echo bad >/opt/mo/mo; then exit 1; fi; '
                            'if echo bad >/result.json; then exit 1; fi; echo denied', 'denied\n')
                    elif name == 'output-bound':
                        result = w.command('yes x', seconds=5)
                        require(result['execution_valid'] and result['truncated'] and result['state'] == 'failure')
                        require(len(base64.b64decode(result['stdout'])) + len(base64.b64decode(result['stderr'])) <= 65536)
                    elif name in ('build-quota', 'tmp-quota'):
                        path, count, size = ('/build', 513, 536870912) if name == 'build-quota' else ('/tmp', 17, 16777216)
                        result = success(w, 'if dd if=/dev/zero of=' + path + '/full bs=1048576 count=' + str(count) +
                            ' 2>/build/dd.log; then exit 1; fi; cat /build/dd.log >&2; wc -c <' + path + '/full; df -k ' + path + ' >&2')
                        require(int(base64.b64decode(result['stdout']).strip()) <= size)
                        require(b'No space left on device' in base64.b64decode(result['stderr']))
                    elif name == 'effective-resources':
                        result = success(w, 'id; cat /proc/self/status; cat /proc/mounts; sleep 1')
                        require(result['observation']['counters'].get('memory.peak', 0) > 0)
                    elif name == 'policy-rebind':
                        w.selection = {}
                        result = w.command('true')
                        require(result['state'] == 'refusal' and result['execution'] == 'not_started')
                    elif name == 'cpu-enforcement':
                        result = success(w, 'echo cpu-probe; (while :; do :; done) & a=$!; '
                            '(while :; do :; done) & b=$!; sleep 3; kill "$a" "$b"; wait || true', seconds=10)
                        require(result['observation']['counters'].get('cpu.stat:nr_throttled', 0) > 0)
                    elif name == 'pids-enforcement':
                        result = w.command('echo pids-probe; i=0; while [ "$i" -lt 160 ]; do sleep 30 & i=$((i+1)); done; wait', seconds=5)
                        require(b'pids-probe' in base64.b64decode(result['stdout']))
                        require(result['observation']['counters'].get('pids.events:max', 0) > 0)
                    elif name == 'memory-enforcement':
                        result = w.command('echo memory-probe; awk \'BEGIN {s="x"; for (i=0;i<31;i++) s=s s; print length(s)}\'; '
                            'rc=$?; echo memory-exit:$rc; sleep 1; exit "$rc"', seconds=30)
                        require(b'memory-probe' in base64.b64decode(result['stdout']))
                        require(result['state'] == 'failure' and result['execution_valid'])
                        require(result['observation']['counters'].get('memory.events:oom_kill', 0) > 0)
                record['ok'] = True
            except Exception:
                record['error'] = traceback.format_exc()
            records.append(record)
            (root / 'controls.json').write_text(json.dumps(records, indent=2))
            print(json.dumps(record), flush=True)
    finally:
        errors = []
        for w in workspaces:
            try:
                if w.active:
                    w.collect()
                w.delete()
            except Exception:
                errors.append({'workspace': w.workspace_id, 'error': traceback.format_exc()})
        inventory = json.loads(py('''import json,pathlib,subprocess,sys
ids=json.loads(sys.argv[1]); r={'directories':[str(p) for i in ids if (p:=pathlib.Path('/var/lib/mo-harness/mo-workspace-'+i)).exists()]}
for key,args in {'containers':['docker','ps','-aq'], 'units':['systemctl','list-units','--all','--no-legend','mo-executor-*'], 'mounts':['findmnt','--json','-o','TARGET'], 'application_tasks':['cat','/sys/fs/cgroup/mo.slice/mo-application.slice/cgroup.procs']}.items():
 p=subprocess.run(args,capture_output=True,text=True,timeout=3); r[key]={'exit':p.returncode,'stdout':p.stdout}
print(json.dumps(r))
''', json.dumps([w.workspace_id for w in workspaces])))
        (root / 'cleanup.json').write_text(json.dumps({'errors': errors, 'inventory': inventory}, indent=2))
        summary = {'controls': len(records), 'passed': sum(r['ok'] for r in records), 'cleanup_errors': errors}
        (root / 'summary.json').write_text(json.dumps(summary, indent=2))
        print(json.dumps(summary), flush=True)
        require(not errors and not inventory['directories'], errors)
        for key in ('containers', 'units', 'application_tasks'):
            require(inventory[key]['exit'] == 0 and not inventory[key]['stdout'].strip(), inventory)
        require(not any(w.workspace_id in inventory['mounts']['stdout'] for w in workspaces))
    require(len(records) == len(names) and all(r['ok'] for r in records), summary)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('directory')
    parser.add_argument('--image', required=True)
    parser.add_argument('--toolchain', required=True)
    parser.add_argument('--controls', nargs='+', choices=CONTROLS, default=list(CONTROLS))
    args = parser.parse_args()
    if len(set(args.controls)) != len(args.controls):
        parser.error('duplicate control selection')
    run(args.directory, args.image, args.toolchain, args.controls)
