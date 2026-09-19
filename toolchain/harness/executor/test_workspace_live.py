"""At most 30 fixed workspace controls. Dedicated released machine only."""
import base64
from functools import partial
import json
import subprocess
from pathlib import Path
import sys
import time
import uuid

from adapter import py, remote
import cases
from cases import require
from selftest import TREE, assert_clean, wait_running
from test_executor import check
from workspace import Workspace, WorkspaceRun
from workspace_files import Refusal


class Suite:
    """The run's workspaces, including the two that several controls share."""
    def __init__(self, root):
        self.root, self.workspaces = root, []
        self.named = cases.Shared(self.workspace)

    def workspace(self, name, entries=None):
        w = Workspace(uuid.uuid4().hex, self.root / name)
        self.workspaces.append(w)
        w.create(entries or {'answer.txt': b'wrong\n'})
        return w


def invalid_import(s):
    failed = Workspace(uuid.uuid4().hex, s.root / 'invalid-import')
    s.workspaces.append(failed)
    entries = {f'tree{i}/a/b/c/d/file': b'x' for i in range(1000)}
    try:
        failed.create(entries)
    except Refusal:
        pass
    else:
        raise AssertionError('inode-exhausting import became ready')
    require(failed.call('list_files')['error'] == 'quarantined')


def hostile(s, name, script, path):
    h = s.workspace(name)
    require(h.command(script)['state'] == 'success')
    require(h.call('read_file', {'path': path})['state'] == 'refusal')
    require(h.call('freeze')['state'] == 'refusal')


def main(directory):
    root = Path(directory)
    root.mkdir(parents=True, exist_ok=False)
    here = Path(__file__).parent
    cases.keep_sources(root, [here / name for name in ('workspace.py', 'workspace_controller.py', 'workspace_files.py',
                                                        'adapter.py', 'remote.py', 'test_workspace_live.py', 'cases.py')])
    s = Suite(root)
    run = cases.Cases(root / 'controls.json')
    run.run(CONTROLS, cases.names(CONTROLS), s)
    errors = cases.delete_all(s.workspaces)
    ids = [w.workspace_id for w in s.workspaces]
    inventory = cases.leftovers(ids)
    (root / 'final-inventory.json').write_text(json.dumps(inventory, indent=2))
    cases.summary(root / 'summary.json', {'controls': len(run.records), 'passed': run.passed, 'cleanup_errors': errors})
    require(not errors, errors)
    cases.require_no_leftovers(inventory, ids)
    require(len(run.records) <= 30 and run.passed == len(run.records), run.records)


def repair(w):
    result = w.command('test "$(cat answer.txt)" = right')
    require(result['state'] == 'failure' and result['exit_code'] == 1, result)
    require(w.read_file('answer.txt') == 'wrong\n')
    require(w.search('wrong')['items'])
    w.exact_edit('answer.txt', 'wrong', 'right')
    result = w.command('test "$(cat answer.txt)" = right && echo repaired')
    require(result['state'] == 'success' and result['exit_code'] == 0, result)


def identities(w):
    call = uuid.uuid4().hex
    require(w.call('list_files', call_id=call)['state'] == 'success')
    try:
        w.call('list_files', call_id=call)
    except Refusal:
        pass
    else:
        raise AssertionError('local duplicate accepted')
    w._calls.remove(call)  # Exercise machine claim with fresh transport evidence.
    original_directory = w.directory
    w.directory = original_directory / 'duplicate-transport'
    w.directory.mkdir()
    try:
        require(w.call('list_files', call_id=call)['error'] == 'duplicate_call')
    finally:
        w.directory = original_directory
    original = w.run_id
    w.run_id = uuid.uuid4().hex
    try:
        require(w.call('list_files')['error'] == 'foreign_run')
    finally:
        w.run_id = original


def file_refusals(w):
    for path in ('../answer.txt', '/etc/passwd', 'a//b', 'a/./b'):
        require(w.call('read_file', {'path': path})['state'] == 'refusal')
    w.write_file('answer.txt', 'aaa')
    require(w.call('exact_edit', {'path': 'answer.txt', 'old': 'aa', 'new': 'b'})['error'] == 'multiple_matches')
    require(w.read_file('answer.txt') == 'aaa')
    require(w.command("printf '\\377' > answer.txt")['state'] == 'success')
    require(w.call('read_file', {'path': 'answer.txt'})['error'] == 'invalid_utf8')
    w.write_file('answer.txt', 'right\n')


def frozen(w):
    require(w.freeze()['snapshot'])
    result = w.verify('cat answer.txt', [check('right\n')])
    require(result['passed'], result)


def closed(w):
    require(w.call('write_file', {'path': 'answer.txt', 'text': 'wrong'})['error'] == 'closed')
    try:
        w.verify('true', [])
    except ValueError:
        pass
    else:
        raise AssertionError('empty checks accepted')


def verification_negatives(w):
    result = w.verify('cat answer.txt', [check('right\n'), check('fault-ran', 'fault', 'contains')])
    require(not result['passed'])
    result = w.verify("if echo forged > answer.txt; then echo overwritten; else echo snapshot-denied; fi; if echo forged > /result.json; then echo overwritten; else echo result-denied; fi", [check('snapshot-denied\nresult-denied\n')])
    require(result['passed'], result)


def wrong(w):
    require(w.command("echo '{\"passed\":true}'")['state'] == 'success')
    w.freeze()
    require(not w.verify('cat answer.txt', [check('right\n')])['passed'])
    require(not w.verify("echo '{\"passed\":true}'", [check('right\n')])['passed'])


def quota(w, inode):
    if inode:
        result = w.command('i=0; while mkdir "d$i" 2>/dev/null; do i=$((i+1)); done; echo inode-full')
        require(result['state'] == 'success', result)
        require(b'inode-full' in base64.b64decode(result['stdout']))
    else:
        # Each container charges only a bounded chunk of tmpfs pages, allowing
        # the workspace quota itself (rather than per-container RAM) to fire.
        exhausted = False
        for i in range(5):
            result = w.command('dd if=/dev/zero of=chunk' + str(i) + ' bs=1048576 count=16 2>&1')
            require(result['execution_valid'], result)
            if b'No space left on device' in base64.b64decode(result['stdout']):
                exhausted = True
                break
        require(exhausted, 'filesystem quota stimulus absent')


def lifecycle(w, mode):
    script = TREE + ('sleep 1; exit 0' if mode == 'exit' else 'wait')
    run = w.start_command(script, seconds=2.5 if mode == 'timeout' else 5)
    wait_running(run)
    require(w.call('list_files')['error'] == 'cleanup_required')
    if mode == 'cancel':
        w.cancel()
    if mode == 'supervisor':
        remote(['systemctl', 'kill', '--kill-whom=main', '--signal=SIGKILL', run.name + '.service'])
        time.sleep(1)
    result = w.collect()
    expected = {'timeout': 'timeout', 'cancel': 'cancellation', 'exit': 'success', 'supervisor': 'failure'}[mode]
    require(result['state'] == expected, result)
    (run.directory / 'after.json').write_text(json.dumps(assert_clean(run), indent=2))
    require(w.read_file('answer.txt') == 'wrong\n')


def mutated(w):
    source = '/var/lib/mo-harness/mo-workspace-' + w.workspace_id + '/snapshot/data/answer.txt'
    # Trusted test fault injection, not candidate authority.
    py('from pathlib import Path; import sys; Path(sys.argv[1]).write_bytes(b"mutated")', source)
    try:
        w.verify('cat answer.txt', [check('mutated')])
    except (RuntimeError, Refusal):
        pass
    else:
        raise AssertionError('mutated snapshot dispatched')


def mode_drift(w):
    source = '/var/lib/mo-harness/mo-workspace-' + w.workspace_id + '/snapshot/data/answer.txt'
    py('import pathlib,sys; p=pathlib.Path(sys.argv[1]); p.write_bytes(b"right\\n"); p.chmod(0o600)', source)
    try:
        w.verify('cat answer.txt', [check('right\n')])
    except (RuntimeError, Refusal):
        pass
    else:
        raise AssertionError('snapshot permission drift dispatched')


def controller_death(w):
    run = w._prepare_command(TREE + 'wait', seconds=4)
    child = None
    try:
        with (run.directory / 'controller.log').open('wb') as log:
            child = subprocess.Popen([sys.executable, '-B', __file__, '--controller', str(run.directory)], stdout=log, stderr=log)
        end = time.monotonic() + 3
        while not (run.directory / 'controller-ready').exists() and time.monotonic() < end:
            require(child.poll() is None, 'controller exited before stimulus')
            time.sleep(.05)
        require((run.directory / 'controller-ready').exists())
        run.manifest = json.loads((run.directory / 'manifest.json').read_text())
        wait_running(run)
        child.kill()
        rc = child.wait(timeout=2)
        require(rc == -9)
        (run.directory / 'controller-exit.json').write_text(json.dumps({'exit_code': rc}))
        time.sleep(max(0, run.manifest['deadline'] + 4 - time.time()))
        (run.directory / 'independent-after.json').write_text(json.dumps(assert_clean(run), indent=2))
        w.collect()
        require(w.read_file('answer.txt') == 'wrong\n')
    finally:
        if child and child.poll() is None:
            child.kill()
            child.wait(timeout=2)


HOSTILE = (('final-symlink', 'ln -s answer.txt link', 'link'),
           ('intermediate-symlink', 'ln -s . link', 'link/answer.txt'),
           ('hardlink', 'ln answer.txt link', 'link'),
           ('fifo', 'mkfifo link', 'link'),
           ('unsupported-mode', 'mkdir link; chmod 4755 answer.txt', 'answer.txt'))
CONTROLS = [
    ('invalid-import-never-ready', invalid_import),
    ('real-failure-inspection-repair-success', lambda s: repair(s.named('repair'))),
    ('duplicate-foreign-calls', lambda s: identities(s.named('repair'))),
    ('invalid-paths-utf8-overlap', lambda s: file_refusals(s.named('repair'))),
    ('freeze-independent-positive', lambda s: frozen(s.named('repair'))),
    ('closed-dispatch-and-empty-checks', lambda s: closed(s.named('repair'))),
    ('missing-stimulus-and-result-overwrite', lambda s: verification_negatives(s.named('repair'))),
    ('wrong-candidate-forged-success', lambda s: wrong(s.named('wrong'))),
    *[(name, partial(hostile, name=name, script=script, path=path)) for name, script, path in HOSTILE],
    ('tmpfs-byte-quota', lambda s: quota(s.workspace('byte-quota'), False)),
    ('tmpfs-inode-quota', lambda s: quota(s.workspace('inode-quota'), True)),
    ('timeout-descendants', lambda s: lifecycle(s.workspace('timeout'), 'timeout')),
    ('cancel-descendants', lambda s: lifecycle(s.workspace('cancel'), 'cancel')),
    ('exit-descendants', lambda s: lifecycle(s.workspace('exit'), 'exit')),
    ('supervisor-death-mounted', lambda s: lifecycle(s.workspace('supervisor'), 'supervisor')),
    ('controller-death-mounted', lambda s: controller_death(s.workspace('controller'))),
    ('stale-mutated-snapshot', lambda s: mutated(s.named('repair'))),
    ('snapshot-permission-drift', lambda s: mode_drift(s.named('repair'))),
]


if __name__ == '__main__':
    if sys.argv[1] == '--controller':
        run = cases.resume(sys.argv[2], WorkspaceRun)
        run.start()
        (run.directory / 'controller-ready').touch()
        run.collect()
    else:
        main(sys.argv[1])
