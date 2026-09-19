"""Fixed recovery groups; explicit selection validated before machine activity."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import time
import uuid
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
from adapter import machine_call, py, sources
import cases
from cases import APPLICATION_IMAGE, APPLICATION_TOOLCHAIN, require
from workspace import Workspace
from recovery import recover, persist


class Suite:
    def __init__(self, output):
        self.output, self.workspaces = output, []

    def new(self, name, application=False, create=True):
        ws = Workspace(uuid.uuid4().hex, self.output / name, **({'policy': 'application-build-v1', 'image': APPLICATION_IMAGE,
                                                                 'toolchain': APPLICATION_TOOLCHAIN} if application else {}))
        self.workspaces.append(ws)
        if create:
            ws.create({'answer': b'recovery\n'})
        return ws


def cleanup(ws):
    # Explicit fault: abandon this test object's lifetime owner before recovery.
    ws.__del__()
    result = recover(ws.directory / 'ownership.json')
    require(result['cleanup'] == 'confirmed', result)
    require(result['execution'] == 'unknown', result)
    return result


def running(ws):
    run = ws.start_command('echo READY; sleep 100 & wait', seconds=10 if not ws.selection else 30)
    reg = cases.until(lambda: cases.registration(run.name), 8, 'candidate never registered')
    (ws.directory / 'running-registration.json').write_text(json.dumps(reg))
    return run


def lost_response(module, name, what):
    """The call takes effect on the machine; its reply is lost on the way back."""
    original = getattr(module, name)
    def lost(*args, **kwargs):
        original(*args, **kwargs)
        raise TimeoutError('test lost ' + what + ' response')
    return patch.object(module, name, side_effect=lost)


def state_identity(ws):
    return json.loads(py("import hashlib,json,pathlib,sys; root=pathlib.Path('/var/lib/mo-harness/mo-workspace-'+sys.argv[1]); print(json.dumps({'state_sha256':hashlib.sha256((root/'state.json').read_bytes()).hexdigest(),'terminal':pathlib.Path('/var/lib/mo-harness/.recovery-'+sys.argv[1]).exists()}))",ws.workspace_id))


def send_request(request):
    return json.loads(machine_call(sources('remote','workspace_files','workspace_controller'),
                                   "sys.modules['workspace_controller'].handle(p['request'])", {'request':request}, 20))


def create_before(s):
    ws = s.new('create-before', create=False)
    cleanup(ws)
    # Replay retained delayed request directly, not via locally closed object.
    request = {'run_id':ws.run_id,'workspace_id':ws.workspace_id,'call_id':uuid.uuid4().hex,
               'operation':'create','args':{'files':[]},'deadline':time.time()+15}
    result = send_request(request)
    require(result['state'] != 'success', result)
    import workspace
    original = workspace.remote
    for suffix, needle in [('before-root', '    root.mkdir(mode=0o700)'),
                           ('before-state', "    state_write(root, state)\n    with lock(root, request['deadline']):")]:
        partial = s.new('create-before-'+suffix, create=False)
        def interrupted(args, data=None, **kwargs):
            payload=json.loads(data)
            source=payload['sources']['workspace_controller']
            require(needle in source, 'missing injection point')
            payload['sources']['workspace_controller']=source.replace(needle,"    raise RuntimeError('test partial create')\n"+needle,1)
            return original(args,data=json.dumps(payload).encode(),**kwargs)
        with patch.object(workspace,'remote',side_effect=interrupted):
            try: partial.create({'a':b'x'})
            except (RuntimeError,ValueError): pass
            else: raise AssertionError('create interruption not injected')
        cleanup(partial)


def create_response(s):
    ws = s.new('create-response', create=False)
    import workspace
    with lost_response(workspace, 'remote', 'create'):
        try: ws.create({'a':b'x'})
        except TimeoutError: pass
        else: raise AssertionError('lost response not injected')
    cleanup(ws)


def reserve_response(s):
    ws = s.new('reserve-response')
    import workspace
    with lost_response(workspace, 'remote', 'reserve'):
        try: ws._prepare_command('echo NEVER')
        except TimeoutError: pass
        else: raise AssertionError('lost response not injected')
    require(ws.active is None)
    cleanup(ws)


def registration_before_reaper(s):
    name = 'registration-before-reaper'
    ws = s.new(name)
    run = ws._prepare_command('echo NEVER')
    ws.ownership['executions'][-1]['dispatch_requested'] = True
    persist(ws)
    # Stop this exact owned bootstrap immediately before reaper installation.
    import adapter
    original = adapter.py
    def interrupted(source, *args, **kwargs):
        source = source.replace(" subprocess.run(['systemd-run','--quiet','--collect','--unit='+name+'-deadline'", " raise RuntimeError('test interruption before reaper')\n subprocess.run(['systemd-run','--quiet','--collect','--unit='+name+'-deadline'")
        return original(source, *args, **kwargs)
    with patch.object(adapter, 'py', side_effect=interrupted):
        try: run.start()
        except RuntimeError: pass
        else: raise AssertionError('injection failed')
    cleanup(ws)
    for suffix in ('before-transport','partial-root'):
        partial = s.new(name+'-'+suffix)
        partial_run=partial._prepare_command('echo NEVER')
        partial.ownership['executions'][-1]['dispatch_requested']=True
        persist(partial)
        if suffix == 'partial-root':
            def partial_bootstrap(source,*args,**kwargs):
                source=source.replace(" root.mkdir(mode=0o700)\n", " root.mkdir(mode=0o700)\n raise RuntimeError('test after root mkdir')\n")
                return original(source,*args,**kwargs)
            with patch.object(adapter,'py',side_effect=partial_bootstrap):
                try: partial_run.start()
                except RuntimeError: pass
                else: raise AssertionError('bootstrap interruption not injected')
        cleanup(partial)


def active_owner_death(s):
    # Child owns the Python object and is killed after actual registration.
    directory = s.output / 'active-owner-death'
    child = subprocess.Popen([sys.executable, '-B', str(HERE / 'owner.py'), str(directory)])
    try:
        def ready():
            require(child.poll() is None, 'owner exited early')
            return (directory / 'ready.json').exists()
        cases.until(ready, 15, 'owner registration timeout')
        child.kill()
        rc = child.wait(timeout=3)
        (directory / 'owner-exit.json').write_text(json.dumps({'exit':rc, 'pid':child.pid}))
        receipt = json.loads((directory / 'ownership.json').read_text())
        result = recover(directory / 'ownership.json')
        require(result['cleanup'] == 'confirmed', result)
        require(result['execution'] == 'unknown')
        (s.output / 'dead-owner-receipt.json').write_text(json.dumps(receipt))
    finally:
        if child.poll() is None:
            child.kill()
            child.wait()


def gap(name):
    """Cleanup after the run is collected, completed or disposed, but before the workspace is."""
    def group(s):
        ws = s.new(name)
        run = running(ws)
        run.cancel()
        run.collect()
        if name in ('complete-gap', 'dispose-gap'):
            ws.require('complete', {'execution_id': run.manifest['run_id']})
        if name == 'dispose-gap':
            run.dispose()
        cleanup(ws)
        if name == 'dispose-gap':
            interrupted_ws = s.new(name + '-interrupted')
            running(interrupted_ws)
            interrupted_ws.__del__()
            import adapter
            original = adapter.remote
            def interrupt_disposal(args, data=None, **kwargs):
                payload = json.loads(data)
                code = payload['sources']['recovery_machine']
                code = code.replace('remote.dispose(eroot, locked=True)', "(eroot / 'manifest.json').unlink(); raise TimeoutError('test partial disposal')")
                payload['sources']['recovery_machine'] = code
                return original(args, data=json.dumps(payload).encode(), **kwargs)
            with patch.object(adapter, 'remote', side_effect=interrupt_disposal):
                result = recover(interrupted_ws.directory / 'ownership.json')
            require(result['cleanup'] == 'unresolved', result)
            cleanup(interrupted_ws)
    return group


def repeated_cleanup(s):
    ws = s.new('repeated-cleanup')
    ws.command('true')
    cleanup(ws)
    cleanup(ws)
    healthy = s.new('repeated-cleanup-healthy-delete')
    healthy.command('true')
    healthy.delete()
    cleanup(healthy)
    cleanup(healthy)


def foreign_identity(s):
    ws = s.new('foreign-identity')
    path = ws.directory / 'ownership.json'
    original = path.read_bytes()
    ws.__del__()
    before = state_identity(ws)
    bad = dict(ws.ownership, run_id=uuid.uuid4().hex)
    path.write_text(json.dumps(bad))
    require(recover(path)['cleanup'] == 'unresolved')
    require(state_identity(ws) == before, 'foreign refusal changed target state/terminal')
    require(not before['terminal'], before)
    path.write_bytes(original)
    cleanup(ws)
    omitted = s.new('foreign-identity-omitted-completed')
    omitted.command('true')
    omitted.__del__()
    path=omitted.directory/'ownership.json'
    original=path.read_bytes()
    before=state_identity(omitted)
    bad=dict(omitted.ownership,executions=[])
    path.write_text(json.dumps(bad))
    result=recover(path)
    require(result['cleanup']=='unresolved' and not result['completed'],result)
    require(state_identity(omitted)==before and not before['terminal'],before)
    path.write_bytes(original)
    cleanup(omitted)


def malformed_linked(s):
    ws = s.new('malformed-linked')
    path = ws.directory / 'ownership.json'
    linked = ws.directory / 'linked.json'
    linked.symlink_to(path)
    try: recover(linked)
    except (ValueError, OSError): pass
    else: raise AssertionError('linked receipt accepted')
    linked.unlink()
    cleanup(ws)


def lock_contention(s):
    ws = s.new('lock-contention')
    running(ws)
    result = recover(ws.directory / 'ownership.json', seconds=.5)
    require(result['cleanup'] == 'unresolved' and result['error'] == 'ownership_busy', result)
    cleanup(ws)


def unknown_transport(s):
    ws = s.new('unknown-transport')
    ws.__del__()
    with patch('adapter.remote', side_effect=TimeoutError('scoped lost transport')):
        result = recover(ws.directory / 'ownership.json')
    require(result['cleanup'] == 'unresolved' and result['execution'] == 'unknown', result)
    cleanup(ws)


def late_bootstrap(s):
    ws = s.new('late-bootstrap')
    run = ws._prepare_command('echo NEVER')
    cleanup(ws)
    try: run.start()
    except RuntimeError: pass
    else: raise AssertionError('late bootstrap accepted')
    cleanup(ws)


def application_active(s):
    ws = s.new('application-active', application=True)
    running(ws)
    cleanup(ws)


def application_snapshot(s):
    ws = s.new('application-snapshot', application=True)
    ws.freeze()
    ws.start_command('echo READY; sleep 100 & wait', seconds=30,
        checks=[{'id':'answer','stream':'stdout','mode':'contains','expected':'READY'}])
    time.sleep(.5)
    cleanup(ws)


TABLE = [
    ('create-before', create_before),
    ('create-response', create_response),
    ('reserve-response', reserve_response),
    ('registration-before-reaper', registration_before_reaper),
    ('active-owner-death', active_owner_death),
    ('finalize-gap', gap('finalize-gap')),
    ('complete-gap', gap('complete-gap')),
    ('dispose-gap', gap('dispose-gap')),
    ('repeated-cleanup', repeated_cleanup),
    ('foreign-identity', foreign_identity),
    ('malformed-linked', malformed_linked),
    ('lock-contention', lock_contention),
    ('unknown-transport', unknown_transport),
    ('late-bootstrap', late_bootstrap),
    ('application-active', application_active),
    ('application-snapshot', application_snapshot),
]
GROUPS = cases.names(TABLE)


def main(output, selected):
    output.mkdir(parents=True, exist_ok=False)
    (output / 'selected.json').write_text(json.dumps({'fixed': GROUPS, 'selected': selected}))
    shared = cases.mac_docker()
    (output / 'shared-before.txt').write_bytes(shared)
    s = Suite(output)
    records = cases.Cases(output / 'results.json', key='group', stop=True)
    try:
        records.run(TABLE, selected, s)
    finally:
        cleanup_results = []
        for ws in s.workspaces:
            ws.__del__()
            cleanup_results.append(recover(ws.directory / 'ownership.json'))
        (output / 'cleanup.json').write_text(json.dumps(cleanup_results, indent=2))
        require(all(r['cleanup'] == 'confirmed' and r['execution'] == 'unknown' for r in cleanup_results), cleanup_results)
        receipts = [w.ownership for w in s.workspaces]
        if (output / 'dead-owner-receipt.json').exists():
            receipts.append(json.loads((output / 'dead-owner-receipt.json').read_text()))
        final = cases.workspace_absence(receipts)
        (output / 'inventory.json').write_text(json.dumps(final, indent=2))
        after = cases.mac_docker()
        (output / 'shared-after.txt').write_bytes(after)
        require(sorted(shared.splitlines()) == sorted(after.splitlines()), 'shared Docker state changed')
        cases.require_absent(final)
    cases.summary(output / 'summary.json', {'groups': len(records.records), 'passed': records.passed})
    require(records.complete(selected), records.records)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('output', type=Path)
    parser.add_argument('--groups', nargs='+', default=list(GROUPS))
    args = parser.parse_args()
    main(args.output, cases.choose(parser, GROUPS, args.groups))
