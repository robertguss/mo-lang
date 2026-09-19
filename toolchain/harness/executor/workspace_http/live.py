"""Explicitly released real Workspace HTTP controls. No local execution fallback."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import time
import uuid
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from workspace_http import Bridge
from workspace_http import protocol as wire
from workspace_http.local import GROUPS
from workspace_http.owner import private_write
from adapter import py
from recovery import recover
from recovery.live import inventory, IMAGE as APP_IMAGE, TOOLCHAIN
from remote import IMAGE, WORKSPACE_POLICY


def require(value, detail='control failed'):
    if not value:
        raise AssertionError(detail)


def start_recorded(bridge):
    return bridge.start(owner_module='workspace_http.live_owner')


def request(bridge, operation='list_files', args=None, call_id=None):
    return dict(version=wire.VERSION, run_id=bridge.run_id, workspace_id=bridge.workspace_id,
                call_id=call_id or uuid.uuid4().hex, operation=operation, args=args or {})


def connect(bridge, req, *, token=None):
    raw = wire.encode(req)
    conn = socket.create_connection(('127.0.0.1', bridge.port), timeout=5)
    conn.sendall((f'POST /tool HTTP/1.1\r\nHost: 127.0.0.1:{bridge.port}\r\n'
                  f'Content-Type: application/json\r\nContent-Length: {len(raw)}\r\n'
                  f'X-Mo-Workspace-Token: {bridge.token if token is None else token}\r\n\r\n').encode() + raw)
    return conn


def response(conn):
    conn.settimeout(305)
    raw = bytearray()
    try:
        while True:
            part = conn.recv(65536)
            if not part:
                break
            raw.extend(part)
            require(len(raw) <= wire.RESPONSE_CAP + 1024, 'wire response bound')
    finally:
        conn.close()
    headers, body = bytes(raw).split(b'\r\n\r\n', 1)
    require(f'Content-Length: {len(body)}'.encode() in headers, 'response length')
    require(b'Connection: close' in headers, 'response close')
    return int(headers.split(b' ')[1]), json.loads(body)


def call(bridge, operation='list_files', args=None, call_id=None):
    return response(connect(bridge, request(bridge, operation, args, call_id)))


def registered(directory):
    end = time.monotonic() + 20
    while time.monotonic() < end:
        receipt = json.loads((directory / 'workspace/ownership.json').read_bytes())
        if receipt['executions']:
            row = receipt['executions'][-1]
            name = 'mo-executor-' + row['execution_id']
            raw = py("""import json,pathlib,subprocess,sys
name=sys.argv[1]; root=pathlib.Path('/tmp')/name
p=subprocess.run(['docker','inspect',name],capture_output=True,timeout=5)
r={'registered':(root/'registration.json').exists(),'running':False}
if p.returncode==0:r['running']=json.loads(p.stdout)[0]['State']['Running']
print(json.dumps(r))
""", name)
            proof = json.loads(raw)
            if proof['registered'] and proof['running']:
                private_write(directory / 'running.json', dict(proof, execution_id=row['execution_id']))
                return
        time.sleep(.1)
    raise AssertionError('actual candidate never observed running')


def finished(directory, seconds=80):
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        result = json.loads((directory / 'owner.json').read_bytes())
        if result['cleanup']['cleanup'] == 'confirmed':
            return result
        time.sleep(.1)
    raise AssertionError('owner cleanup not confirmed')


def prove_dead(directory):
    pid = json.loads((directory / 'owner.json').read_bytes())['owner_pid']
    deadline = time.monotonic() + 3
    while time.monotonic() < deadline:
        probe = subprocess.run(['ps', '-p', str(pid), '-o', 'pid=,stat=,command='], capture_output=True, timeout=2)
        text = probe.stdout.decode().strip()
        if not text or (len(text.split()) > 1 and text.split()[1].startswith('Z')):
            private_write(directory / 'owner-death-proof.json', {'pid': pid, 'ps_exit': probe.returncode, 'output': text, 'dead': True})
            return
        time.sleep(.05)
    raise AssertionError('owner death not proved')


def shared():
    return subprocess.run(['docker', 'ps', '-a', '--no-trunc', '--format', '{{.ID}} {{.State}}'],
                          capture_output=True, check=True, timeout=10).stdout


def main(output, groups, application):
    output.mkdir(parents=True, exist_ok=False)
    private_write(output / 'selected.json', {'groups': groups, 'fixed': GROUPS, 'application': application})
    before = shared()
    (output / 'shared-before.txt').write_bytes(before)
    require(len(before.splitlines()) == 5, 'shared baseline count')
    selected = {'policy': 'application-build-v1', 'image': APP_IMAGE, 'toolchain': TOOLCHAIN} if application else {
        'policy': WORKSPACE_POLICY, 'image': IMAGE, 'toolchain': None}
    verifier = {'script': 'cat /workspace/answer', 'seconds': 2,
                'checks': [{'id': 'answer', 'stream': 'stdout', 'mode': 'exact', 'expected': 'after\n'}]}
    bridges, directories, results = [], [], []

    def new(name, selection=None):
        directory = output / name
        bridge = Bridge('http-' + name, directory,
                        {'answer': b'before\n', 'unicode': 'hé🌊\n'.encode(), 'large': b'x' * 65536},
                        selection=selection or selected, verifier=verifier)
        bridges.append(bridge)
        directories.append(directory)
        if name == 'startup-failure':
            (directory / 'test-lost-create').touch()
        return start_recorded(bridge)

    def command(b, script, timeout=1000, call_id=None):
        return call(b, 'command', {'command': script, 'timeout_ms': timeout}, call_id)

    def action(group):
        if group == 'invalid-selection':
            target = output / group
            try:
                Bridge('invalid', target, {}, selection=dict(selected, policy='invalid'), verifier=verifier)
            except ValueError:
                require(not target.exists())
                return
            raise AssertionError('invalid selection accepted')
        if group == 'frontend-death':
            directory = output / group
            config = dict(run_id='actual-parent-death', directory=str(directory), selection=selected, verifier=verifier)
            config_path = output / 'frontend-config.json'
            private_write(config_path, config)
            env = dict(os.environ, PYTHONPATH=str(Path(__file__).resolve().parents[1]))
            log = (output / 'frontend.log').open('xb')
            child = subprocess.Popen([sys.executable, '-B', '-m', 'workspace_http.live_frontend', str(config_path)],
                                     env=env, stdout=log, stderr=log)
            log.close()
            directories.append(directory)
            try:
                end = time.monotonic() + 45
                while not (directory / 'ready.json').exists():
                    require(child.poll() is None, 'frontend failed startup')
                    require(time.monotonic() < end, 'frontend readiness timeout')
                    time.sleep(.1)
                from types import SimpleNamespace
                ready = json.loads((directory / 'ready.json').read_bytes())
                token = json.loads((directory / 'capability.json').read_bytes())['token']
                b = SimpleNamespace(**ready, token=token)
                conn = connect(b, request(b, 'command', {'command': 'echo RUNNING; sleep 6; echo DONE', 'timeout_ms': 9000}))
                registered(directory)
                child.kill()
                private_write(output / 'frontend-exit.json', {'pid': child.pid, 'exit': child.wait(timeout=3)})
                conn.close()
                result = finished(directory)
                require(next(iter(result['calls'].values()))['result']['execution'] == 'completed')
            finally:
                if child.poll() is None:
                    child.kill(); child.wait(timeout=3)
            return
        if group == 'startup-failure':
            try:
                new(group)
            except EOFError:
                b = bridges[-1]
                require(b.close())
                require(not (b.directory / 'ready.json').exists())
                require(json.loads((b.directory / 'owner.json').read_bytes())['cleanup']['cleanup'] == 'confirmed')
                return
            raise AssertionError('lost create response was not injected')
        b = new(group)
        if group == 'six-tools':
            require(call(b)[1]['state'] == 'success')
            require(call(b, 'read_file', {'path': 'unicode'})[1]['result']['text'] == 'hé🌊\n')
            require(call(b, 'search', {'query': '🌊'})[1]['result']['items'][0]['offset'] == 3)
            require(call(b, 'write_file', {'path': 'answer', 'text': 'middle\n'})[1]['result']['written'])
            require(call(b, 'exact_edit', {'path': 'answer', 'old_text': 'middle', 'new_text': 'after'})[1]['result']['edited'])
            result = command(b, 'cat /workspace/answer')[1]
            require(result['execution'] == 'completed' and result['result']['stdout'] == 'after\n', result)
        elif group == 'output-encoding':
            require(command(b, "printf '\\377'")[1]['error'] == 'output_encoding')
            require(command(b, 'cat /workspace/unicode')[1]['result']['stdout'] == 'hé🌊\n')
        elif group in ('schema', 'framing', 'identities-capability'):
            req = request(b)
            if group == 'schema':
                req['args']['extra'] = 'no'
                status, result = response(connect(b, req))
                require(status == 400)
            elif group == 'identities-capability':
                status, result = response(connect(b, req, token='wrong'))
                require(status == 401)
            else:
                conn = socket.create_connection(('127.0.0.1', b.port), timeout=5)
                conn.sendall(b'GET /tool HTTP/1.1\r\n\r\n')
                status, result = response(conn)
                require(status == 405)
            require(not result['accepted'])
            require(not json.loads((b.directory / 'owner.json').read_bytes())['calls'])
        elif group in ('byte-bounds', 'file-refusals'):
            path = 'large' if group == 'byte-bounds' else '../escape'
            result = call(b, 'read_file', {'path': path})[1]
            require(result['state'] == 'refusal' and result['execution'] == 'completed', result)
            require(result['error'] == ('result_too_large' if group == 'byte-bounds' else 'invalid_path'), result)
        elif group == 'duplicate-calls':
            command(b, 'echo once >> /workspace/answer', call_id='once')
            require(command(b, 'echo twice >> /workspace/answer', call_id='once')[0] == 409)
            require(call(b, 'read_file', {'path': 'answer'})[1]['result']['text'] == 'before\nonce\n')
        elif group in ('concurrent-admission', 'disconnect', 'lost-response', 'owner-death'):
            conn = connect(b, request(b, 'command', {'command': 'echo EFFECT > /workspace/answer; sleep 6', 'timeout_ms': 9000}))
            registered(b.directory)
            if group == 'concurrent-admission':
                require(call(b)[0] == 409)
                require(response(conn)[1]['execution'] == 'completed')
            elif group == 'owner-death':
                b.stop_owner()
                conn.close()
                recovery = b.recover()
                require(recovery['cleanup'] == 'confirmed' and recovery['execution'] == 'unknown', recovery)
            else:
                conn.close()
                result = finished(b.directory)
                require(len(result['calls']) == 1)
                require(next(iter(result['calls'].values()))['result']['execution'] == 'completed')
        elif group in ('deadlines', 'cleanup-outcome'):
            if group == 'deadlines':
                from workspace_http.controller_deadline import check
                check(b.directory)
            result = command(b, 'sleep 6', 500)[1]
            require(result['state'] == 'timeout' and result['execution'] == 'completed', result)
            if group == 'cleanup-outcome':
                require(b.close())
                import adapter
                original_remote = adapter.remote
                def lost_cleanup(*args, **kwargs):
                    original_remote(*args, **kwargs)
                    raise TimeoutError('test actual lost cleanup response')
                with patch.object(adapter, 'remote', side_effect=lost_cleanup):
                    unknown = b.recover()
                require(unknown['cleanup'] == 'unresolved' and unknown['execution'] == 'unknown', unknown)
                confirmed = b.recover()
                require(confirmed['cleanup'] == 'confirmed' and confirmed['execution'] == 'unknown', confirmed)
        elif group == 'owner-stall':
            # A bounded live command is the serialized stall; close cannot clean concurrently.
            conn = connect(b, request(b, 'command', {'command': 'sleep 6', 'timeout_ms': 9000}))
            registered(b.directory)
            require(not b.close(seconds=.01), 'running owner incorrectly reported exited')
            conn.close()
            require(b.process.poll() is None)
            finished(b.directory)
        elif group == 'protected-verifier':
            call(b, 'write_file', {'path': 'answer', 'text': 'after\n'})
            b.freeze()
            result = b.verify()
            require(result['passed'], result)
            # Candidate never receives host verifier or operator config.
            require(result['manifest']['workspace']['readonly'])
        elif group == 'application-binding':
            # Selection is externally supplied and fixed, never read from candidate args.
            script = f'test ! -e /Users && test ! -e /private && test ! -e {b.directory}/config.json && test ! -e /workspace/config.json && echo ISOLATED'
            result = command(b, script, 120000 if application else 1000)[1]
            require(result['result']['stdout'] == 'ISOLATED\n', result)
            core_path = next(b.directory.glob('core-*.json'))
            core = json.loads(core_path.read_bytes())
            require(core['manifest']['policy'] == selected['policy'])
            require(core['manifest']['image'] == selected['image'])
        elif group == 'journal-order-bound':
            for i in range(16):
                require(call(b, call_id='c' + str(i))[1]['accepted'])
            require(call(b, call_id='overflow')[0] == 409)
            journal = json.loads((b.directory / 'owner.json').read_bytes())
            require(len(journal['calls']) == 16)
            for row in journal['calls'].values():
                require(row['intent'] and len(row['payload_sha256']) == 64)
                require((b.directory / 'workspace' / ('call-' + row['core_call_id']) / 'request.json').exists())
        elif group == 'shutdown':
            require(b.close())
        else:
            raise AssertionError('unimplemented group ' + group)

    failure = None
    try:
        for group in groups:
            started = time.monotonic()
            try:
                action(group)
                # Finish each owned workspace before the next group; no live overlap.
                for b in bridges:
                    require(b.close(), 'owner did not exit')
                results.append({'group': group, 'passed': True, 'elapsed': time.monotonic() - started})
                print(group, 'PASS', flush=True)
            except Exception as exc:
                results.append({'group': group, 'passed': False, 'error': repr(exc)})
                raise
    except BaseException as exc:
        failure = exc
    finally:
        private_write(output / 'results-before-cleanup.json', results)
        if failure is not None:
            private_write(output / 'failure.json', {'type': type(failure).__name__, 'detail': str(failure)})
        for b in bridges:
            if not b.close():
                b.stop_owner()
            receipt = b.directory / 'workspace/ownership.json'
            if receipt.exists():
                # Separate cleanup-only invocation after proved original child death.
                recovered = b.recover()
                require(recovered['cleanup'] == 'confirmed', recovered)
        receipts = [json.loads((directory / 'workspace/ownership.json').read_bytes()) for directory in directories
                    if (directory / 'workspace/ownership.json').exists()]
        # Parent-death owner must finish before explicit recovery; receipt never adopts.
        for directory in directories:
            if all(b.directory != directory for b in bridges):
                finished(directory)
                prove_dead(directory)
                result = recover(directory / 'workspace/ownership.json', seconds=60)
                require(result['cleanup'] == 'confirmed', result)
        source_proofs = []
        for directory in directories:
            config_path = directory / 'config.json'
            if not config_path.exists():
                continue
            config = json.loads(config_path.read_bytes())
            journal = json.loads((directory / 'owner.json').read_bytes())
            call_path = directory / 'workspace' / ('call-' + journal['creation_call_id']) / 'request.json'
            actual = json.loads(call_path.read_bytes())
            require(dict(actual['args']['files']) == config['source'], 'imported source mismatch')
            require(actual['run_id'] == journal['core_run_id'] and actual['workspace_id'] == journal['core_workspace_id'])
            source_proofs.append({'directory': directory.name, 'source_sha256': hashlib.sha256(wire.encode(config['source'])).hexdigest(),
                                  'core_request_sha256': hashlib.sha256(call_path.read_bytes()).hexdigest(), 'matched': True})
        private_write(output / 'source-proofs.json', source_proofs)
        proof = inventory(receipts)
        private_write(output / 'absence.json', proof)
        require(all(not item['root_exists'] and not item['mounts'] and all(
            not e['root_exists'] and not e['containers'].strip() and not e['units'].strip() and not e['cgroup_exists']
            for e in item['executions']) for item in proof), proof)
        after = shared()
        (output / 'shared-after.txt').write_bytes(after)
        require(sorted(before.splitlines()) == sorted(after.splitlines()), 'shared Mac inventory changed')
        private_write(output / 'results.json', results)
    if failure:
        raise failure
    print(json.dumps({'groups': len(results), 'passed': len(results), 'actual_workspace': True, 'acceptance': False}))

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('output', type=Path)
    parser.add_argument('--groups', default=','.join(GROUPS))
    parser.add_argument('--application', action='store_true')
    args = parser.parse_args()
    groups = args.groups.split(',')
    if not groups or len(groups) != len(set(groups)) or any(name not in GROUPS for name in groups):
        parser.error('unknown, empty or duplicate group selection')
    main(args.output.resolve(), groups, args.application)
