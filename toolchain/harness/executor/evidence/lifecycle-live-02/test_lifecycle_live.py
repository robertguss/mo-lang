"""Collector death after failed ExecStopPost and uncertain explicit cleanup."""
import json
from pathlib import Path
import shutil
import subprocess
import sys
import time

import adapter
from adapter import Run, py, remote
from selftest import TREE, assert_clean, resume, snapshot, wait_running
from test_executor import check


def fault_collector(directory):
    run = resume(directory)
    real_py, real_command = adapter.py, subprocess.run

    def fault_py(source, *args, **kwargs):
        if 'ExecStopPost=-/usr/bin/docker' in source:
            old = "'--property=ExecStopPost=-/usr/bin/docker rm -f '+name"
            assert old in source
            source = source.replace(old, "'--property=ExecStopPost=/usr/bin/false'")
            (run.directory / 'fault-bootstrap.py').write_text(source)
        elif 'observation.json' in source:
            raise RuntimeError('injected observation transport loss')
        elif 'from remote import finalize;' in source:
            source = source.replace('from remote import finalize;',
                "import remote as machine; machine.cleanup=lambda name: {'absent':False,'removed_rc':1}; from remote import finalize;")
            (run.directory / 'fault-finalizer.py').write_text(source)
        return real_py(source, *args, **kwargs)

    def fault_command(args, **kwargs):
        if args == ['orbctl', 'stop', adapter.MACHINE]:
            # Parent kills this controller before its fallback shutdown. The
            # machine's untouched independent reaper must finish the cleanup.
            (run.directory / 'cleanup-uncertain').write_text('host reached fail-closed fallback; shutdown not dispatched')
            time.sleep(20)
            raise RuntimeError('parent did not kill collector')
        return real_command(args, **kwargs)

    adapter.py = fault_py
    subprocess.run = fault_command
    run.start()
    wait_running(run)
    run.collect()
    raise AssertionError('fault collector unexpectedly returned')


def main(directory):
    root = Path(directory); root.mkdir(parents=True, exist_ok=False)
    for name in ('adapter.py', 'remote.py', 'test_lifecycle_live.py'):
        shutil.copyfile(Path(__file__).with_name(name), root / name)
    run = Run(TREE + 'wait', [check('parent\n', mode='contains')], root / 'collector-gap', seconds=5)
    child = None
    try:
        with (root / 'collector.log').open('wb') as log:
            child = subprocess.Popen([sys.executable, '-B', __file__, '--collector', str(run.directory)], stdout=log, stderr=log)
        end = time.monotonic() + 4
        while not (run.directory / 'cleanup-uncertain').exists() and time.monotonic() < end:
            if child.poll() is not None: raise AssertionError('collector exited before fault stimulus')
            time.sleep(.05)
        assert (run.directory / 'cleanup-uncertain').exists(), 'cleanup fault not reached'
        run = resume(run.directory)
        before = snapshot(run)
        (root / 'uncertain-before-death.json').write_text(json.dumps(before, indent=2))
        assert before['containers']['stdout'].strip(), 'candidate must survive failed stop/cleanup'
        assert before['cgroup_exists'], 'candidate cgroup stimulus absent'
        armed = remote(['systemctl', 'is-active', run.name + '-deadline.timer']).decode().strip()
        assert armed == 'active', armed
        journal = remote(['journalctl', '--no-pager', '-n', '30', '-o', 'cat', '-u', run.name + '.service'])
        (root / 'supervisor-journal.txt').write_bytes(journal)
        assert b'status=1/FAILURE' in journal, 'ExecStopPost exit 1 not observed'
        proof = py("from pathlib import Path; import sys; print(Path(sys.argv[1],'cleanup-confirmed.json').exists())", run.root)
        assert proof.strip() == b'False', 'cleanup must remain unconfirmed'
        assert not (run.directory / 'result.json').exists(), 'no final verdict before cleanup proof'
        child.kill(); child_rc = child.wait(timeout=2)
        assert child_rc == -9
        (root / 'collector-kill.json').write_text(json.dumps({'exit_code': child_rc, 'timer_before_kill': armed}))
        time.sleep(max(0, run.manifest['deadline'] + 4 - time.time()))
        after = snapshot(run)
        (root / 'independent-after.json').write_text(json.dumps(after, indent=2))
        assert_clean(run, after)
        reaped = json.loads(py("from pathlib import Path; import sys; print(Path(sys.argv[1],'reaped.json').read_text())", run.root))
        (root / 'reaped.json').write_text(json.dumps(reaped, indent=2))
        assert reaped['absent'] and reaped['cgroup_absent'], reaped
        result = run.collect()
        assert not result['passed']
        assert result['observation']['cleanup']['ordering'] == ['supervisor_stopped', 'container_absent', 'cgroup_absent', 'deadline_units_stopped', 'units_absent']
        print(json.dumps({'passed': True, 'controls': 1, 'collector_exit_code': child_rc,
                          'independent_cleanup': reaped, 'final_status': result['observation']['status']}, indent=2))
    finally:
        if child and child.poll() is None: child.kill(); child.wait(timeout=2)
        run = resume(run.directory)
        run.collect()
        run.dispose()


if __name__ == '__main__':
    if sys.argv[1] == '--collector': fault_collector(sys.argv[2])
    else: main(sys.argv[1])
