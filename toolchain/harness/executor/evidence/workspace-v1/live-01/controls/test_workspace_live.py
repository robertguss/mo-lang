"""At most 30 fixed workspace controls. Dedicated released machine only."""
import base64
import json
from pathlib import Path
import shutil
import sys
import time
import traceback
import uuid

from adapter import py, remote
from selftest import TREE, assert_clean, wait_running, snapshot
from test_executor import check
from workspace import Workspace
from workspace_files import Refusal


def require(value, detail=None):
    if not value:
        raise AssertionError(detail)


def main(directory):
    root = Path(directory)
    root.mkdir(parents=True, exist_ok=False)
    records = []
    workspaces = []
    for name in ('workspace.py', 'workspace_controller.py', 'workspace_files.py', 'adapter.py', 'remote.py', 'test_workspace_live.py'):
        shutil.copyfile(Path(__file__).with_name(name), root / name)

    def workspace(name, entries=None):
        w = Workspace(uuid.uuid4().hex, root / name)
        workspaces.append(w)
        w.create(entries or {'answer.txt': b'wrong\n'})
        return w

    def case(name, action):
        record = {'case': name, 'ok': False}
        try:
            action()
            record['ok'] = True
        except Exception:
            record['error'] = traceback.format_exc()
        records.append(record)
        print(json.dumps(record), flush=True)
        (root / 'controls.json').write_text(json.dumps(records, indent=2))

    w = workspace('repair')
    case('real-failure-inspection-repair-success', lambda: repair(w))
    case('duplicate-foreign-calls', lambda: identities(w))
    case('invalid-paths-utf8-overlap', lambda: file_refusals(w))
    case('freeze-independent-positive', lambda: frozen(w))
    case('closed-dispatch-and-empty-checks', lambda: closed(w))
    case('missing-stimulus-and-result-overwrite', lambda: verification_negatives(w))

    bad = workspace('wrong')
    case('wrong-candidate-forged-success', lambda: wrong(bad))

    for name, script, path in (
        ('final-symlink', 'ln -s answer.txt link', 'link'),
        ('intermediate-symlink', 'ln -s . link', 'link/answer.txt'),
        ('hardlink', 'ln answer.txt link', 'link'),
        ('fifo', 'mkfifo link', 'link'),
        ('special-socket', 'mkdir link; chmod 4755 answer.txt', 'answer.txt'),
    ):
        def hostile(name=name, script=script, path=path):
            h = workspace(name)
            require(h.command(script)['state'] == 'success')
            require(h.call('read_file', {'path': path})['state'] == 'refusal')
            require(h.call('freeze')['state'] == 'refusal')
        case(name, hostile)

    case('tmpfs-byte-quota', lambda: quota(workspace('byte-quota'), False))
    case('tmpfs-inode-quota', lambda: quota(workspace('inode-quota'), True))
    case('timeout-descendants', lambda: lifecycle(workspace('timeout'), 'timeout'))
    case('cancel-descendants', lambda: lifecycle(workspace('cancel'), 'cancel'))
    case('exit-descendants', lambda: lifecycle(workspace('exit'), 'exit'))
    case('supervisor-death-mounted', lambda: lifecycle(workspace('supervisor'), 'supervisor'))
    case('stale-mutated-snapshot', lambda: mutated(w))

    cleanup_errors = []
    for ws in workspaces:
        try:
            if ws.active:
                ws.collect()
            ws.delete()
        except Exception:
            cleanup_errors.append({'workspace_id': ws.workspace_id, 'error': traceback.format_exc()})
    inventory = json.loads(py("""import json,pathlib,subprocess,sys
ids=json.loads(sys.argv[1]); roots=[pathlib.Path('/var/lib/mo-harness/mo-workspace-'+i) for i in ids]
r={'directories':[str(p) for p in roots if p.exists()]}
for key,args in {'containers':['docker','ps','-aq','--filter','name=^/mo-executor-'], 'units':['systemctl','list-units','--all','--no-legend','mo-executor-*'], 'mounts':['findmnt','--json','-o','TARGET']}.items():
 p=subprocess.run(args,capture_output=True,text=True,timeout=3); r[key]={'rc':p.returncode,'stdout':p.stdout}
print(json.dumps(r))
""", json.dumps([ws.workspace_id for ws in workspaces])))
    (root / 'final-inventory.json').write_text(json.dumps(inventory, indent=2))
    summary = {'controls': len(records), 'passed': sum(r['ok'] for r in records), 'cleanup_errors': cleanup_errors}
    (root / 'summary.json').write_text(json.dumps(summary, indent=2))
    print(json.dumps(summary), flush=True)
    require(not cleanup_errors, cleanup_errors)
    require(not inventory['directories'], inventory)
    for key in ('containers', 'units'):
        require(inventory[key]['rc'] == 0 and not inventory[key]['stdout'].strip(), inventory)
    require(not any(ws.workspace_id in inventory['mounts']['stdout'] for ws in workspaces), inventory)
    require(len(records) <= 30 and all(r['ok'] for r in records), summary)


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
    w._calls.remove(call)  # Exercise trusted machine claim, bypassing local cache.
    require(w.call('list_files', call_id=call)['error'] == 'duplicate_call')
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
    script = ('i=0; while mkdir "d$i" 2>/dev/null; do i=$((i+1)); done; echo inode-full' if inode else
              'dd if=/dev/zero of=full bs=1048576 count=70 2>/tmp/quota-error; rc=$?; cat /tmp/quota-error; test "$rc" != 0 && echo byte-full')
    result = w.command(script)
    require(result['state'] == 'success', result)
    out = base64.b64decode(result['stdout'])
    require((b'inode-full' if inode else b'No space left on device') in out, out)


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


if __name__ == '__main__':
    main(sys.argv[1])
