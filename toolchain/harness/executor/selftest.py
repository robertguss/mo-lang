"""Fixed live acceptance controls. Run only through the repository guard (600s)."""
import base64
from functools import partial
import json
import os
from pathlib import Path
import signal
import shlex
import subprocess
import sys
import time

from adapter import Run, py, remote
import cases
from cases import require
from test_executor import check

TREE = '''echo parent
/bin/sh -c 'echo child; /bin/sh -c "echo grandchild; sleep 30" & wait' &
setsid /bin/sh -c 'echo session; sleep 30' &
'''


def snapshot(run):
    source = '''import json,pathlib,subprocess,sys
n=sys.argv[1]
def cmd(a):
 p=subprocess.run(a,capture_output=True,text=True,timeout=3); return {'rc':p.returncode,'stdout':p.stdout,'stderr':p.stderr}
r={'containers':cmd(['docker','ps','-aq','--filter','name=^/'+n+'$']), 'units':cmd(['systemctl','list-units','--all','--no-legend',n+'*'])}
i=cmd(['docker','inspect',n]); r['inspect']=i
if i['rc']==0:
 v=json.loads(i['stdout'])[0]
 parent=subprocess.run(['systemctl','show','--property=ControlGroup','--value','mo-executor.slice'],capture_output=True,text=True,check=True).stdout.strip()
 r['cgroup']='/sys/fs/cgroup'+parent+'/docker-'+v['Id']+'.scope'
 r['cgroup_exists']=pathlib.Path(r['cgroup']).exists()
 r['top']=cmd(['docker','top',n,'-eo','pid,ppid,sid,args'])
print(json.dumps(r))
'''
    return json.loads(py(source, run.name))


def wait_running(run):
    end = time.monotonic() + 3
    while time.monotonic() < end:
        snap = snapshot(run)
        if snap.get('top', {}).get('rc') == 0 and 'sleep 30' in snap['top']['stdout']:
            # A child, grandchild and independent session must actually exist.
            rows = snap['top']['stdout'].splitlines()[1:]
            processes = [tuple(map(int, row.split()[:3])) for row in rows]
            parent = json.loads(snap['inspect']['stdout'])[0]['State']['Pid']
            children = {pid for pid, ppid, sid in processes if ppid == parent}
            grandchildren = {pid for pid, ppid, sid in processes if ppid in children}
            new_session = {pid for pid, ppid, sid in processes if pid == sid and pid != parent}
            if children and grandchildren and new_session and snap['cgroup_exists']:
                (run.directory / 'running.json').write_text(json.dumps(snap, indent=2))
                return snap
        time.sleep(.1)
    raise AssertionError('descendant stimulus never observed')


def assert_clean(run, snap=None):
    snap = snap or snapshot(run)
    assert snap['containers']['rc'] == 0 and not snap['containers']['stdout'].strip(), snap
    assert snap['units']['rc'] == 0 and not snap['units']['stdout'].strip(), snap
    running = run.directory / 'running.json'
    if running.exists():
        group = json.loads(running.read_text())['cgroup']
        assert py('from pathlib import Path; import sys; print(Path(sys.argv[1]).exists())', group).strip() == b'False'
    return snap


def resume(directory):
    return cases.resume(directory, Run)


def controller_child(directory):
    r = resume(directory)
    r.start()
    (r.directory / 'controller-ready').write_text(str(os.getpid()))
    r.collect()


def executed(script, checks, outcome='completed', passed=True, seconds=5, action=None, assertion=None, *, root, name):
    r = Run(script(root) if callable(script) else script, checks, root / name, seconds)
    # Always explicit scoped cleanup, even when an assertion failed.
    with cases.then(lambda: (r.collect(), r.dispose())):
        r.start()
        if action: action(r)
        result = r.collect()
        observation = result['observation']
        assert observation['status'] == outcome, (observation['status'], observation.get('error'))
        assert result['passed'] is passed, (result['passed'], result['checks'])
        assert result['identity_valid'] and result['policy_valid'], (result['identity_valid'], result['policy_valid'])
        assert all(observation['cleanup'].get(k) for k in ('absent', 'cgroup_absent', 'host_confirmed')), observation
        if outcome != 'completed': assert all(c['passed'] for c in result['checks']), result['checks']
        if assertion: assertion(result)
        (r.directory / 'after.json').write_text(json.dumps(assert_clean(r), indent=2))
        return cases.Fields(status=observation['status'], exit_code=observation['exit_code'], check_count=len(result['checks']))


def died(mode, *, root, name):
    """The controller or the supervisor dies mid-run; the machine's own reaper cleans up."""
    r = Run(TREE + 'wait', TREE_CHECKS, root / name, seconds=3)
    record, child = {}, None
    def cleanup():
        if child and child.poll() is None: child.kill(); child.wait(timeout=2)
        r.collect(); r.dispose()
    with cases.then(cleanup):
        if mode == 'controller':
            with (r.directory / 'controller.log').open('wb') as log:
                child = subprocess.Popen([sys.executable, '-B', __file__, '--controller', str(r.directory)], stdout=log, stderr=log)
            def ready():
                if child.poll() is not None: raise AssertionError('controller died before stimulus')
                return (r.directory / 'controller-ready').exists()
            cases.until(ready, 4, 'controller never started the run', .05)
            r = resume(r.directory)
            wait_running(r)
            child.kill(); record['controller_exit_code'] = child.wait(timeout=2)
            assert record['controller_exit_code'] == -signal.SIGKILL
        else:
            r.start(); wait_running(r)
            remote(['systemctl', 'kill', '--kill-whom=main', '--signal=SIGKILL', r.name + '.service'])
            record['kill_command_rc'] = 0
        # No controller cleanup until an independent post-deadline observation.
        time.sleep(max(0, r.manifest['deadline'] + 4 - time.time()))
        snap = snapshot(r)
        (r.directory / 'independent-after.json').write_text(json.dumps(snap, indent=2))
        assert_clean(r, snap)
        reaped = json.loads(py("from pathlib import Path; import sys; print(Path(sys.argv[1],'reaped.json').read_text())", r.root))
        assert reaped['absent'], reaped
        (r.directory / 'reaped.json').write_text(json.dumps(reaped, indent=2))
        result = r.collect()
        assert not result['passed']
        if mode == 'supervisor': assert result['observation']['status'] == 'infrastructure_failure'
        return cases.Fields(record, status=result['observation']['status'], check_count=len(result['checks']))


def completion_control(run):
    wait_running(run)
    try:
        run.dispose()
    except RuntimeError as exc:
        assert 'cannot dispose an active run' in str(exc), str(exc)
        (run.directory / 'active-dispose-rejected.txt').write_text(str(exc))
    else:
        raise AssertionError('active run disposal was allowed')


def overwrite_authority(root):
    target = shlex.quote(str((root / 'overwrite-authority' / 'result.json').resolve()))
    return f'''echo overwrite-probe
mkdir /tmp/fake-result
printf '{{"passed":true}}' > /tmp/fake-result/result.json
if echo forged > {target}; then echo host-overwrite; else echo host-result-denied; fi
if echo forged > /result.json; then echo root-overwrite; else echo denied; fi
echo wrong'''


TREE_CHECKS = [check(x+'\n', x, 'contains') for x in ('parent', 'child', 'grandchild', 'session')]
CASES = [(name, partial(action, *args, **options)) for name, action, args, options in [
    ('completion-descendants', executed, (TREE + 'echo stderr-control >&2; sleep 1; exit 0',
     TREE_CHECKS + [check('stderr-control\n', 'stderr', stream='stderr')]), dict(action=completion_control)),
    ('wrong-output', executed, ('echo wrong', [check()]), dict(passed=False)),
    ('nonzero', executed, ('echo ok; exit 7', [check()]), dict(passed=False,
     assertion=lambda r: require(r['observation']['exit_code'] == 7))),
    ('forged-success', executed, ('echo \'{"passed":true,"checks":["ok"]}\'', [check()]), dict(passed=False)),
    ('overwrite-authority', executed, (overwrite_authority, [check()]), dict(passed=False,
     assertion=lambda r: require(b'host-result-denied\n' in base64.b64decode(r['observation']['stdout'])))),
    ('fault-stimulus-control', executed, ('if echo x > /root-write; then exit 1; else echo fault-ran; echo ok; fi',
     [check('ok\n', mode='contains'), check('fault-ran\n', 'fault', 'contains')]), {}),
    ('absent-fault-stimulus', executed, ('echo ok', [check(), check('fault-ran', 'fault', 'contains')]), dict(passed=False)),
    ('timeout-descendants', executed, (TREE + 'wait', TREE_CHECKS), dict(outcome='timeout', passed=False,
     seconds=2.5, action=wait_running)),
    ('cancel-descendants', executed, (TREE + 'wait', TREE_CHECKS), dict(outcome='cancelled', passed=False,
     action=lambda r: (wait_running(r), r.cancel()))),
    ('output-overflow', executed, ('echo output-probe; while :; do echo 012345678901234567890123456789 >&2; done',
     [check('output-probe\n')]), dict(outcome='output_overflow', passed=False,
     assertion=lambda r: require(sum(len(base64.b64decode(r['observation'][s])) for s in ('stdout','stderr')) == 65536))),
    ('cpu-enforcement', executed, ('echo cpu-probe; while :; do :; done', [check('cpu-probe\n')]),
     dict(outcome='timeout', passed=False, seconds=2,
     assertion=lambda r: require(r['observation']['counters']['cpu.stat:nr_throttled'] > 0))),
    ('memory-enforcement', executed, ('''echo memory-probe
awk 'BEGIN {s="x"; for (i=0;i<28;i++) s=s s; print length(s)}'
r=$?; echo memory-exit:$r; sleep .5; exit $r''', [check('memory-probe\n', mode='contains')]), dict(passed=False,
     assertion=lambda r: require(r['observation']['counters']['memory.events:oom_kill'] > 0 and all(c['passed'] for c in r['checks'])))),
    ('pid-enforcement', executed, ('''echo pid-probe
/bin/sh -c 'i=0; while [ "$i" -lt 40 ]; do sleep 30 & i=$((i+1)); done; wait' &
while :; do :; done''', [check('pid-probe\n')]), dict(outcome='timeout', passed=False, seconds=2.5,
     assertion=lambda r: require(r['observation']['counters']['pids.events:max'] > 0))),
    ('scratch-enforcement', executed, ('''echo scratch-probe
for p in /work /tmp; do
 echo writable > "$p/small" || exit 1
 rm "$p/small"
 if dd if=/dev/zero of="$p/full" bs=1048576 count=9 2>/dev/null; then exit 2; fi
 echo "$p:$(stat -c %s "$p/full")"
done''', [check('scratch-probe\n/work:8388608\n/tmp:8388608\n')]), {}),
    ('network-filesystem-denial', executed, ('''echo boundary-probe
id -u
printf loopback-ok > /work/index.html
httpd -f -p 127.0.0.1:8080 -h /work &
sleep .2
wget -qO- http://127.0.0.1:8080/ || exit 1
echo
if wget -T 1 -qO /tmp/network http://192.0.2.1/; then exit 2; else echo network-denied; fi
if echo x > /root-write; then exit 3; else echo root-denied; fi
for p in /var/run/docker.sock /mnt/mac /Users /run/host-services/ssh-auth.sock; do
 [ ! -e "$p" ] || exit 4
done
echo mounts-absent
[ -r /proc/self/status ] || exit 5
while read key value rest; do
 case "$key" in CapEff:|NoNewPrivs:) echo "$key$value";; esac
done < /proc/self/status''', [check('boundary-probe\n65534\nloopback-ok\nnetwork-denied\nroot-denied\nmounts-absent\nCapEff:0000000000000000\nNoNewPrivs:1\n')]), {}),
    ('controller-death', died, ('controller',), {}),
    ('supervisor-death', died, ('supervisor',), {}),
]]


def main(directory):
    root = Path(directory)
    root.mkdir(parents=True, exist_ok=False)
    here = Path(__file__).parent
    cases.keep_sources(root, [here / name for name in ('adapter.py', 'remote.py', 'selftest.py', 'test_executor.py', 'cases.py')])
    inventory = remote(['docker', 'ps', '-a', '--no-trunc', '--format', '{{json .}}'])
    (root / 'inventory-before.txt').write_bytes(inventory)
    run = cases.Cases(root / 'cases.json')
    for name, action in CASES:
        run.one(name, partial(action, root=root, name=name))
    after = remote(['docker', 'ps', '-a', '--no-trunc', '--format', '{{json .}}'])
    (root / 'inventory-after.txt').write_bytes(after)
    units = remote(['systemctl', 'list-units', '--all', '--no-legend', 'mo-executor-*'])
    (root / 'units-after.txt').write_bytes(units)
    final = {'cases': run.records, 'count': len(run.records), 'passed': run.passed,
             'inventory_unchanged': inventory == after, 'units_empty': not units.strip(),
             'artifact_bytes': sum(p.stat().st_size for p in root.rglob('*') if p.is_file())}
    cases.summary(root / 'summary.json', final, indent=2)
    return 0 if run.passed == len(CASES) and inventory == after and not units.strip() and final['artifact_bytes'] <= 16*1024*1024 else 1


if __name__ == '__main__':
    if sys.argv[1] == '--controller': controller_child(sys.argv[2])
    else: raise SystemExit(main(sys.argv[1]))
