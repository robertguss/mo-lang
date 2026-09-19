"""Fixed recovery groups; explicit selection validated before machine activity."""
import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time
import traceback
import uuid
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
from adapter import py, remote
from workspace import Workspace
from recovery import recover, persist

GROUPS = ('create-before', 'create-response', 'reserve-response', 'registration-before-reaper',
          'active-owner-death', 'finalize-gap', 'complete-gap', 'dispose-gap', 'repeated-cleanup',
          'foreign-identity', 'malformed-linked', 'lock-contention', 'unknown-transport',
          'late-bootstrap', 'application-active', 'application-snapshot')
IMAGE = 'sha256:b9fda4ae85f369e475e0f412e15dea9044a849a64bc2ec94bb3bc5a661eab3c4'
TOOLCHAIN = 'd31b5c5e7e1912f98eba21268854d0f7b830dba7048b2de0e2c0458d10e507eb'


def require(value, detail=None):
    if not value:
        raise AssertionError(detail)


def inventory(receipts):
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


def main(output, selected):
    output.mkdir(parents=True, exist_ok=False)
    (output / 'selected.json').write_text(json.dumps({'fixed': GROUPS, 'selected': selected}))
    workspaces = []
    records = []
    shared = subprocess.run(['docker', 'ps', '-a', '--no-trunc', '--format', '{{.ID}} {{.State}}'], capture_output=True, timeout=10, check=True).stdout
    (output / 'shared-before.txt').write_bytes(shared)

    def new(name, application=False, create=True):
        ws = Workspace(uuid.uuid4().hex, output / name,
                       **({'policy': 'application-build-v1', 'image': IMAGE, 'toolchain': TOOLCHAIN} if application else {}))
        workspaces.append(ws)
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
        end = time.monotonic() + 8
        while time.monotonic() < end:
            raw = py("import pathlib,sys; p=pathlib.Path(sys.argv[1], 'registration.json'); print(p.read_text() if p.exists() else '{}')", run.root)
            reg = json.loads(raw)
            active = json.loads(py("import json,subprocess,sys; p=subprocess.run(['docker','inspect',sys.argv[1]],capture_output=True); print(json.dumps(json.loads(p.stdout)[0]['State']['Running'] if p.returncode==0 else False))", run.name))
            if reg and active:
                (ws.directory / 'running-registration.json').write_text(json.dumps(reg))
                return run
            time.sleep(.1)
        raise AssertionError('candidate never registered')

    def action(name):
        if name == 'create-before':
            ws = new(name, create=False)
            cleanup(ws)
            # Replay retained delayed request directly, not via locally closed object.
            request = {'run_id':ws.run_id,'workspace_id':ws.workspace_id,'call_id':uuid.uuid4().hex,
                       'operation':'create','args':{'files':[]},'deadline':time.time()+15}
            result = send_request(request)
            require(result['state'] != 'success', result)
            import workspace
            original = workspace.remote
            for suffix, needle in [('before-root', '    root.mkdir(mode=0o700)'),
                                   ('before-state', '    state_write(root, state)\n    with lock(root, request['deadline']):')]:
                partial = new(name+'-'+suffix, create=False)
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
        elif name == 'create-response':
            ws = new(name, create=False)
            import workspace
            original = workspace.remote
            def lost(*args, **kwargs):
                original(*args, **kwargs)
                raise TimeoutError('test lost create response')
            with patch.object(workspace, 'remote', side_effect=lost):
                try: ws.create({'a':b'x'})
                except TimeoutError: pass
                else: raise AssertionError('lost response not injected')
            cleanup(ws)
        elif name == 'reserve-response':
            ws = new(name)
            import workspace
            original = workspace.remote
            def lost(*args, **kwargs):
                original(*args, **kwargs)
                raise TimeoutError('test lost reserve response')
            with patch.object(workspace, 'remote', side_effect=lost):
                try: ws._prepare_command('echo NEVER')
                except TimeoutError: pass
                else: raise AssertionError('lost response not injected')
            require(ws.active is None)
            cleanup(ws)
        elif name == 'registration-before-reaper':
            ws = new(name)
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
                partial = new(name+'-'+suffix)
                partial_run=partial._prepare_command('echo NEVER')
                partial.ownership['executions'][-1]['dispatch_requested']=True
                persist(partial)
                if suffix == 'partial-root':
                    def partial_bootstrap(source,*args,**kwargs):
                        source=source.replace(" (root/'remote.py').write_text(p['source'])", " raise RuntimeError('test after root mkdir')\n (root/'remote.py').write_text(p['source'])")
                        return original(source,*args,**kwargs)
                    with patch.object(adapter,'py',side_effect=partial_bootstrap):
                        try: partial_run.start()
                        except RuntimeError: pass
                        else: raise AssertionError('bootstrap interruption not injected')
                cleanup(partial)
        elif name == 'active-owner-death':
            # Child owns the Python object and is killed after actual registration.
            directory = output / name
            child = subprocess.Popen([sys.executable, '-B', str(HERE / 'owner.py'), str(directory)])
            try:
                end = time.monotonic() + 15
                marker = directory / 'ready.json'
                while not marker.exists() and time.monotonic() < end:
                    require(child.poll() is None, 'owner exited early')
                    time.sleep(.1)
                require(marker.exists(), 'owner registration timeout')
                child.kill()
                rc = child.wait(timeout=3)
                (directory / 'owner-exit.json').write_text(json.dumps({'exit':rc, 'pid':child.pid}))
                receipt = json.loads((directory / 'ownership.json').read_text())
                result = recover(directory / 'ownership.json')
                require(result['cleanup'] == 'confirmed', result)
                require(result['execution'] == 'unknown')
                (output / 'dead-owner-receipt.json').write_text(json.dumps(receipt))
            finally:
                if child.poll() is None:
                    child.kill()
                    child.wait()
        elif name in ('finalize-gap', 'complete-gap', 'dispose-gap'):
            ws = new(name)
            run = running(ws)
            run.cancel()
            run.collect()
            if name in ('complete-gap', 'dispose-gap'):
                ws.require('complete', {'execution_id': run.manifest['run_id']})
            if name == 'dispose-gap':
                run.dispose()
            cleanup(ws)
            if name == 'dispose-gap':
                interrupted_ws = new(name + '-interrupted')
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
        elif name == 'repeated-cleanup':
            ws = new(name)
            ws.command('true')
            cleanup(ws)
            cleanup(ws)
            healthy = new(name+'-healthy-delete')
            healthy.command('true')
            healthy.delete()
            cleanup(healthy)
            cleanup(healthy)
        elif name == 'foreign-identity':
            ws = new(name)
            path = ws.directory / 'ownership.json'
            original = path.read_bytes()
            ws.__del__()
            bad = dict(ws.ownership, run_id=uuid.uuid4().hex)
            path.write_text(json.dumps(bad))
            require(recover(path)['cleanup'] == 'unresolved')
            path.write_bytes(original)
            cleanup(ws)
            omitted = new(name+'-omitted-completed')
            omitted.command('true')
            omitted.__del__()
            path=omitted.directory/'ownership.json'
            original=path.read_bytes()
            bad=dict(omitted.ownership,executions=[])
            path.write_text(json.dumps(bad))
            result=recover(path)
            require(result['cleanup']=='unresolved' and not result['completed'],result)
            path.write_bytes(original)
            cleanup(omitted)
        elif name == 'malformed-linked':
            ws = new(name)
            path = ws.directory / 'ownership.json'
            linked = ws.directory / 'linked.json'
            linked.symlink_to(path)
            try: recover(linked)
            except (ValueError, OSError): pass
            else: raise AssertionError('linked receipt accepted')
            linked.unlink()
            cleanup(ws)
        elif name == 'lock-contention':
            from recovery import owner_lock
            ws = new(name)
            running(ws)
            result = recover(ws.directory / 'ownership.json', seconds=.5)
            require(result['cleanup'] == 'unresolved' and result['error'] == 'ownership_busy', result)
            cleanup(ws)
        elif name == 'unknown-transport':
            ws = new(name)
            ws.__del__()
            with patch('adapter.remote', side_effect=TimeoutError('scoped lost transport')):
                result = recover(ws.directory / 'ownership.json')
            require(result['cleanup'] == 'unresolved' and result['execution'] == 'unknown', result)
            cleanup(ws)
        elif name == 'late-bootstrap':
            ws = new(name)
            run = ws._prepare_command('echo NEVER')
            cleanup(ws)
            try: run.start()
            except RuntimeError: pass
            else: raise AssertionError('late bootstrap accepted')
            cleanup(ws)
        elif name == 'application-active':
            ws = new(name, application=True)
            running(ws)
            cleanup(ws)
        elif name == 'application-snapshot':
            ws = new(name, application=True)
            ws.freeze()
            run = ws.start_command('echo READY; sleep 100 & wait', seconds=30,
                checks=[{'id':'answer','stream':'stdout','mode':'contains','expected':'READY'}])
            time.sleep(.5)
            cleanup(ws)
        else:
            raise AssertionError(name)

    try:
        for name in selected:
            record = {'group':name, 'ok':False}
            try:
                action(name)
                record['ok'] = True
            except Exception:
                record['error'] = traceback.format_exc()
            records.append(record)
            (output / 'results.json').write_text(json.dumps(records, indent=2))
            print(json.dumps(record), flush=True)
            if not record['ok']:
                break
    finally:
        cleanup_results = []
        for ws in workspaces:
            ws.__del__()
            cleanup_results.append(recover(ws.directory / 'ownership.json'))
        (output / 'cleanup.json').write_text(json.dumps(cleanup_results, indent=2))
        receipts = [w.ownership for w in workspaces]
        if (output / 'dead-owner-receipt.json').exists():
            receipts.append(json.loads((output / 'dead-owner-receipt.json').read_text()))
        final = inventory(receipts)
        (output / 'inventory.json').write_text(json.dumps(final, indent=2))
        after = subprocess.run(['docker', 'ps', '-a', '--no-trunc', '--format', '{{.ID}} {{.State}}'], capture_output=True, timeout=10, check=True).stdout
        (output / 'shared-after.txt').write_bytes(after)
        require(sorted(shared.splitlines()) == sorted(after.splitlines()), 'shared Docker state changed')
        for row in final:
            require(not row['root_exists'] and not row['mounts'], row)
            for execution in row['executions']:
                require(not any(execution[k] for k in ('root_exists','containers','units','cgroup_exists')), execution)
    require(len(records) == len(selected) and all(r['ok'] for r in records), records)


def send_request(request):
    sources = {name:(HERE.parent / (name+'.py')).read_text() for name in ('remote','workspace_files','workspace_controller')}
    source = """import json,sys,types
p=json.load(sys.stdin)
for name,source in p['sources'].items():
 m=types.ModuleType(name);sys.modules[name]=m;exec(compile(source,name+'.py','exec'),m.__dict__)
print(json.dumps(sys.modules['workspace_controller'].handle(p['request'])))
"""
    return json.loads(remote(['python3','-c',source], data=json.dumps({'sources':sources,'request':request}).encode(), timeout=20))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('output', type=Path)
    parser.add_argument('--groups', nargs='+', default=list(GROUPS))
    args = parser.parse_args()
    if not args.groups or len(set(args.groups)) != len(args.groups) or set(args.groups) - set(GROUPS):
        parser.error('unknown, empty, or duplicate recovery selection')
    main(args.output, args.groups)
