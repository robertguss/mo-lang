"""Explicitly released real Workspace HTTP controls. No local execution fallback."""
import argparse
from functools import partial
import hashlib
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
from types import SimpleNamespace
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import cases
from cases import APPLICATION_IMAGE, APPLICATION_TOOLCHAIN, require
from workspace_http import Bridge
from workspace_http import protocol as wire
from workspace_http.client import GROUPS, connect, request
from workspace_http.client import response as read_response
from workspace_http.owner import private_write
from recovery import recover
from remote import IMAGE, WORKSPACE_POLICY


def start_recorded(bridge):
    return bridge.start(owner_module='workspace_http.live_owner')


def response(conn):
    return read_response(conn, 305)


def call(bridge, operation='list_files', args=None, call_id=None):
    return response(connect(bridge, request(bridge, operation, args, call_id)))


def registered(directory):
    def running():
        receipt = json.loads((directory / 'workspace/ownership.json').read_bytes())
        row = receipt['executions'][-1] if receipt['executions'] else None
        return row if row and cases.registration('mo-executor-' + row['execution_id']) is not None else None
    row = cases.until(running, 20, 'actual candidate never observed running')
    private_write(directory / 'running.json', {'registered': True, 'running': True, 'execution_id': row['execution_id']})


def finished(directory, seconds=80):
    def confirmed():
        result = json.loads((directory / 'owner.json').read_bytes())
        return result if result['cleanup']['cleanup'] == 'confirmed' else None
    return cases.until(confirmed, seconds, 'owner cleanup not confirmed')


def prove_dead(directory):
    pid = json.loads((directory / 'owner.json').read_bytes())['owner_pid']
    def dead():
        probe = subprocess.run(['ps', '-p', str(pid), '-o', 'pid=,stat=,command='], capture_output=True, timeout=2)
        text = probe.stdout.decode().strip()
        if not text or (len(text.split()) > 1 and text.split()[1].startswith('Z')):
            private_write(directory / 'owner-death-proof.json', {'pid': pid, 'ps_exit': probe.returncode, 'output': text, 'dead': True})
            return True
    cases.until(dead, 3, 'owner death not proved', .05)


class Suite:
    def __init__(self, output, application):
        self.output, self.application = output, application
        self.selection = {'policy': 'application-build-v1', 'image': APPLICATION_IMAGE, 'toolchain': APPLICATION_TOOLCHAIN} if application else {
            'policy': WORKSPACE_POLICY, 'image': IMAGE, 'toolchain': None}
        self.verifier = {'script': 'cat /workspace/answer', 'seconds': 2,
                         'checks': [{'id': 'answer', 'stream': 'stdout', 'mode': 'exact', 'expected': 'after\n'}]}
        self.bridges, self.directories = [], []

    def new(self, name):
        directory = self.output / name
        bridge = Bridge('http-' + name, directory,
                        {'answer': b'before\n', 'unicode': 'hé🌊\n'.encode(), 'large': b'x' * 65536},
                        selection=self.selection, verifier=self.verifier)
        self.bridges.append(bridge)
        self.directories.append(directory)
        if name == 'startup-failure':
            (directory / 'test-lost-create').touch()
        return start_recorded(bridge)

    def close_all(self):
        # Finish each owned workspace before the next group; no live overlap.
        for b in self.bridges:
            require(b.close(), 'owner did not exit')


def command(b, script, timeout=1000, call_id=None):
    return call(b, 'command', {'command': script, 'timeout_ms': timeout}, call_id)


def invalid_selection(s, name):
    target = s.output / name
    try:
        Bridge('invalid', target, {}, selection=dict(s.selection, policy='invalid'), verifier=s.verifier)
    except ValueError:
        require(not target.exists())
        return
    raise AssertionError('invalid selection accepted')


def frontend_death(s, name):
    directory = s.output / name
    config = dict(run_id='actual-parent-death', directory=str(directory), selection=s.selection, verifier=s.verifier)
    config_path = s.output / 'frontend-config.json'
    private_write(config_path, config)
    env = dict(os.environ, PYTHONPATH=str(Path(__file__).resolve().parents[1]))
    log = (s.output / 'frontend.log').open('xb')
    child = subprocess.Popen([sys.executable, '-B', '-m', 'workspace_http.live_frontend', str(config_path)],
                             env=env, stdout=log, stderr=log)
    log.close()
    s.directories.append(directory)
    try:
        def ready():
            require(child.poll() is None, 'frontend failed startup')
            return (directory / 'ready.json').exists()
        cases.until(ready, 45, 'frontend readiness timeout')
        ready = json.loads((directory / 'ready.json').read_bytes())
        token = json.loads((directory / 'capability.json').read_bytes())['token']
        b = SimpleNamespace(**ready, token=token)
        conn = connect(b, request(b, 'command', {'command': 'echo RUNNING; sleep 6; echo DONE', 'timeout_ms': 9000}))
        registered(directory)
        child.kill()
        private_write(s.output / 'frontend-exit.json', {'pid': child.pid, 'exit': child.wait(timeout=3)})
        conn.close()
        result = finished(directory)
        require(next(iter(result['calls'].values()))['result']['execution'] == 'completed')
    finally:
        if child.poll() is None:
            child.kill(); child.wait(timeout=3)


def startup_failure(s, name):
    try:
        s.new(name)
    except EOFError:
        b = s.bridges[-1]
        require(b.close())
        require(not (b.directory / 'ready.json').exists())
        require(json.loads((b.directory / 'owner.json').read_bytes())['cleanup']['cleanup'] == 'confirmed')
        return
    raise AssertionError('lost create response was not injected')


def six_tools(s, name):
    b = s.new(name)
    require(call(b)[1]['state'] == 'success')
    require(call(b, 'read_file', {'path': 'unicode'})[1]['result']['text'] == 'hé🌊\n')
    require(call(b, 'search', {'query': '🌊'})[1]['result']['items'][0]['offset'] == 3)
    require(call(b, 'write_file', {'path': 'answer', 'text': 'middle\n'})[1]['result']['written'])
    require(call(b, 'exact_edit', {'path': 'answer', 'old_text': 'middle', 'new_text': 'after'})[1]['result']['edited'])
    result = command(b, 'cat /workspace/answer')[1]
    require(result['execution'] == 'completed' and result['result']['stdout'] == 'after\n', result)


def output_encoding(s, name):
    b = s.new(name)
    require(command(b, "printf '\\377'")[1]['error'] == 'output_encoding')
    require(command(b, 'cat /workspace/unicode')[1]['result']['stdout'] == 'hé🌊\n')


def rejected(s, name):
    """schema, framing, identities-capability: refused at admission, nothing journaled."""
    b = s.new(name)
    req = request(b)
    if name == 'schema':
        req['args']['extra'] = 'no'
        status, result = response(connect(b, req))
        require(status == 400)
    elif name == 'identities-capability':
        status, result = response(connect(b, req, token='wrong'))
        require(status == 401)
    else:
        conn = socket.create_connection(('127.0.0.1', b.port), timeout=5)
        conn.sendall(b'GET /tool HTTP/1.1\r\n\r\n')
        status, result = response(conn)
        require(status == 405)
    require(not result['accepted'])
    require(not json.loads((b.directory / 'owner.json').read_bytes())['calls'])


def file_refused(s, name):
    """byte-bounds, file-refusals: a completed refusal of one read."""
    b = s.new(name)
    path = 'large' if name == 'byte-bounds' else '../escape'
    result = call(b, 'read_file', {'path': path})[1]
    require(result['state'] == 'refusal' and result['execution'] == 'completed', result)
    require(result['error'] == ('result_too_large' if name == 'byte-bounds' else 'invalid_path'), result)


def duplicate_calls(s, name):
    b = s.new(name)
    command(b, 'echo once >> /workspace/answer', call_id='once')
    require(command(b, 'echo twice >> /workspace/answer', call_id='once')[0] == 409)
    require(call(b, 'read_file', {'path': 'answer'})[1]['result']['text'] == 'before\nonce\n')


def in_flight(s, name):
    """concurrent-admission, disconnect, lost-response, owner-death: something happens mid-command."""
    b = s.new(name)
    conn = connect(b, request(b, 'command', {'command': 'echo EFFECT > /workspace/answer; sleep 6', 'timeout_ms': 9000}))
    registered(b.directory)
    if name == 'concurrent-admission':
        require(call(b)[0] == 409)
        require(response(conn)[1]['execution'] == 'completed')
    elif name == 'owner-death':
        b.stop_owner()
        conn.close()
        recovery = b.recover()
        require(recovery['cleanup'] == 'confirmed' and recovery['execution'] == 'unknown', recovery)
    else:
        conn.close()
        result = finished(b.directory)
        require(len(result['calls']) == 1)
        require(next(iter(result['calls'].values()))['result']['execution'] == 'completed')


def timed_out(s, name):
    """deadlines, cleanup-outcome: a command outlives its timeout."""
    b = s.new(name)
    if name == 'deadlines':
        from workspace_http.controller_deadline import check
        check(b.directory)
    result = command(b, 'sleep 6', 500)[1]
    require(result['state'] == 'timeout' and result['execution'] == 'completed', result)
    if name == 'cleanup-outcome':
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


def owner_stall(s, name):
    # A bounded live command is the serialized stall; close cannot clean concurrently.
    b = s.new(name)
    conn = connect(b, request(b, 'command', {'command': 'sleep 6', 'timeout_ms': 9000}))
    registered(b.directory)
    require(not b.close(seconds=.01), 'running owner incorrectly reported exited')
    conn.close()
    require(b.process.poll() is None)
    finished(b.directory)


def protected_verifier(s, name):
    b = s.new(name)
    call(b, 'write_file', {'path': 'answer', 'text': 'after\n'})
    b.freeze()
    result = b.verify()
    require(result['passed'], result)
    # Candidate never receives host verifier or operator config.
    require(result['manifest']['workspace']['readonly'])


def application_binding(s, name):
    # Selection is externally supplied and fixed, never read from candidate args.
    b = s.new(name)
    script = f'test ! -e /Users && test ! -e /private && test ! -e {b.directory}/config.json && test ! -e /workspace/config.json && echo ISOLATED'
    result = command(b, script, 120000 if s.application else 1000)[1]
    require(result['result']['stdout'] == 'ISOLATED\n', result)
    core = json.loads(next(b.directory.glob('core-*.json')).read_bytes())
    require(core['manifest']['policy'] == s.selection['policy'])
    require(core['manifest']['image'] == s.selection['image'])


def journal_order_bound(s, name):
    b = s.new(name)
    for i in range(16):
        require(call(b, call_id='c' + str(i))[1]['accepted'])
    require(call(b, call_id='overflow')[0] == 409)
    journal = json.loads((b.directory / 'owner.json').read_bytes())
    require(len(journal['calls']) == 16)
    for row in journal['calls'].values():
        require(row['intent'] and len(row['payload_sha256']) == 64)
        require((b.directory / 'workspace' / ('call-' + row['core_call_id']) / 'request.json').exists())


TABLE = {
    'six-tools': six_tools, 'output-encoding': output_encoding, 'schema': rejected, 'framing': rejected,
    'byte-bounds': file_refused, 'identities-capability': rejected, 'duplicate-calls': duplicate_calls,
    'concurrent-admission': in_flight, 'file-refusals': file_refused, 'deadlines': timed_out,
    'disconnect': in_flight, 'frontend-death': frontend_death, 'owner-death': in_flight,
    'lost-response': in_flight, 'owner-stall': owner_stall, 'startup-failure': startup_failure,
    'shutdown': lambda s, name: require(s.new(name).close()), 'protected-verifier': protected_verifier,
    'application-binding': application_binding, 'cleanup-outcome': timed_out,
    'invalid-selection': invalid_selection, 'journal-order-bound': journal_order_bound,
}
assert tuple(TABLE) == GROUPS


def source_proofs(directories):
    """Each started owner imported exactly the configured source."""
    proofs = []
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
        proofs.append({'directory': directory.name, 'source_sha256': hashlib.sha256(wire.encode(config['source'])).hexdigest(),
                       'core_request_sha256': hashlib.sha256(call_path.read_bytes()).hexdigest(), 'matched': True})
    return proofs


def main(output, groups, application):
    output.mkdir(parents=True, exist_ok=False)
    private_write(output / 'selected.json', {'groups': groups, 'fixed': GROUPS, 'application': application})
    before = cases.mac_docker()
    (output / 'shared-before.txt').write_bytes(before)
    require(len(before.splitlines()) == 5, 'shared baseline count')
    s = Suite(output, application)
    records = cases.Cases(output / 'results-before-cleanup.json', key='group', stop=True)
    try:
        records.run([(name, partial(TABLE[name], name=name)) for name in groups], groups, s, after=s.close_all)
    finally:
        failed = [record for record in records.records if not record['ok']]
        if failed:
            private_write(output / 'failure.json', failed[0])
        for b in s.bridges:
            if not b.close():
                b.stop_owner()
            if (b.directory / 'workspace/ownership.json').exists():
                # Separate cleanup-only invocation after proved original child death.
                recovered = b.recover()
                require(recovered['cleanup'] == 'confirmed', recovered)
        receipts = [json.loads((directory / 'workspace/ownership.json').read_bytes()) for directory in s.directories
                    if (directory / 'workspace/ownership.json').exists()]
        # Parent-death owner must finish before explicit recovery; receipt never adopts.
        for directory in s.directories:
            if all(b.directory != directory for b in s.bridges):
                finished(directory)
                prove_dead(directory)
                result = recover(directory / 'workspace/ownership.json', seconds=60)
                require(result['cleanup'] == 'confirmed', result)
        private_write(output / 'source-proofs.json', source_proofs(s.directories))
        proof = cases.workspace_absence(receipts)
        private_write(output / 'absence.json', proof)
        cases.require_absent(proof)
        after = cases.mac_docker()
        (output / 'shared-after.txt').write_bytes(after)
        require(sorted(before.splitlines()) == sorted(after.splitlines()), 'shared Mac inventory changed')
        private_write(output / 'results.json', records.records)
    require(records.complete(groups), records.records)
    print(json.dumps({'groups': len(records.records), 'passed': records.passed, 'actual_workspace': True, 'acceptance': False}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('output', type=Path)
    parser.add_argument('--groups', default=','.join(GROUPS))
    parser.add_argument('--application', action='store_true')
    args = parser.parse_args()
    main(args.output.resolve(), cases.choose(parser, GROUPS, args.groups.split(',')), args.application)
