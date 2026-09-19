"""Independent loopback fixtures. Candidate command text is an inert dictionary key."""
import argparse
import contextlib
import http.server
import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parents[5]
HERE = Path(__file__).resolve().parent
MO = os.environ.get('MO_BIN', str(ROOT/'toolchain/zig-out/bin/mo'))
GUARD = ['python3', str(ROOT/'toolchain/bench/step36/guard.py')]


def invoke(args, seconds=60, cwd=ROOT):
    command = GUARD + [str(seconds), '--'] + args
    # A process group owns the guard and every descendant, including on timeout.
    with tempfile.TemporaryFile() as out, tempfile.TemporaryFile() as err:
        proc = subprocess.Popen(command, cwd=cwd, stdout=out, stderr=err, start_new_session=True)
        try:
            code = proc.wait(timeout=seconds + 3)
        except subprocess.TimeoutExpired:
            code = 124
        finally:
            with contextlib.suppress(ProcessLookupError):
                os.killpg(proc.pid, signal.SIGKILL)
            proc.wait()
        out.seek(0); err.seek(0)
        stdout, stderr = out.read(2**20), err.read(2**20)
    return dict(command=command, exit_code=code, stdout=stdout.decode(errors='replace'), stderr=stderr.decode(errors='replace'))


def tool(name, **args):
    return dict(tool=name, args=args, tokens=0)


def response(request, **updates):
    result = dict(version=1, run_id=request['run_id'], call_id=request['call_id'],
                  workspace_id=request['workspace_id'], state='success', exit_code=0,
                  stdout='', stderr='', stdout_truncated=False, stderr_truncated=False,
                  elapsed_ms=0, error_code='none', execution='completed')
    result.update(updates)
    return result


CASES = ['repair', 'edit-missing', 'edit-duplicate', 'edit-overlap', 'edit-empty',
         'edit-original-size', 'edit-result-size', 'edit-path', 'edit-unicode',
         'command-refusal', 'command-failure', 'command-nonzero', 'command-timeout',
         'command-cancellation', 'command-malformed', 'command-identity', 'command-truncation',
         'command-output-size', 'command-type', 'command-transport', 'model-missing-usage',
         'tokens', 'steps', 'context']


# Each exact_edit refusal and the reason the run records for it; the file stays as it was.
REFUSALS = {'edit-missing': 'missing_match', 'edit-duplicate': 'multiple_matches',
            'edit-overlap': 'multiple_matches', 'edit-empty': 'empty_match',
            'edit-original-size': 'size', 'edit-path': 'invalid_path'}


def case(name, mode):
    with tempfile.TemporaryDirectory(prefix='mo-coding-fixture-') as tmp:
        root = Path(tmp)
        (root/'work').mkdir()
        original = 'broken\n'
        reply = tool('command', command='test-key')
        expected_code, terminal = 0, 'done'
        if name.startswith('edit-'):
            old, new = 'broken', 'fixed'
            if name == 'edit-missing': old = 'absent'
            if name == 'edit-duplicate': original = 'broken broken'
            if name == 'edit-overlap': original, old = 'aaa', 'aa'
            if name == 'edit-empty': old = ''
            if name == 'edit-original-size': original = 'x'*65537
            if name == 'edit-result-size': new = 'x'*65537
            if name == 'edit-unicode': original, old, new = 'a\u0301 / café\n', '\u0301', '!'
            reply = tool('exact_edit', path='../escape' if name == 'edit-path' else 'target.txt', old_text=old, new_text=new)
        if name == 'edit-result-size':
            expected_code, terminal = 3, 'over_budget'
        if name == 'repair':
            replies = [reply, tool('read_file', path='target.txt'), tool('exact_edit', path='target.txt', old_text='broken', new_text='fixed'), reply, dict(done='repaired', tokens=0)]
        elif name == 'model-missing-usage':
            replies = [dict(done='missing')]
            expected_code, terminal = 3, 'failed'
        elif name == 'tokens':
            replies = [dict(tool='read_file', args=dict(path='target.txt'), tokens=4097)]
            expected_code, terminal = 3, 'over_budget'
        elif name == 'steps':
            replies = [tool('read_file', path='target.txt')]*9
            expected_code, terminal = 3, 'over_budget'
        elif name == 'context':
            original = 'x'*65536
            replies = [tool('read_file', path='target.txt'), dict(done='must not dispatch', tokens=0)]
            expected_code, terminal = 3, 'over_budget'
        else:
            replies = [reply, dict(done='observed', tokens=0)]
        if name in ['command-timeout', 'command-cancellation', 'command-malformed', 'command-identity', 'command-output-size', 'command-type', 'command-transport']:
            expected_code, terminal = 3, 'failed'
        (root/'work/target.txt').write_text(original)
        requests, errors = [], []

        class Handler(http.server.BaseHTTPRequestHandler):
            def setup(self):
                super().setup()
                self.connection.settimeout(3)
            def log_message(self, *_): pass
            def do_POST(self):
                try:
                    raw = self.rfile.read(int(self.headers['Content-Length']))
                    request = json.loads(raw)
                    logs = list((root/'runs').glob('*.log'))
                    lines = [json.loads(line) for line in logs[0].read_text().splitlines()] if logs else []
                    recorded = [line['step'] for line in lines if 'step' in line]
                    requests.append(dict(path=self.path, body=request, recorded=recorded))
                    if self.path == '/complete':
                        assert request['transcript'] == recorded, 'model dispatched before recording acknowledgement'
                        index = sum(r['path'] == '/complete' for r in requests)-1
                        result = replies[index] if index < len(replies) else dict(done='unexpected dispatch', tokens=0)
                    else:
                        assert self.path == '/fixture/v1/command'
                        assert recorded[-1]['kind'] == 'model'
                        assert request['version'] == 1 and request['workspace_id'] == 'opaque-workspace'
                        assert request['run_id'] == 'r_1' and request['call_id'] == str(len(recorded)+1)
                        assert 0 < request['timeout_ms'] <= 2000 and request['max_output_bytes'] == 65536
                        result = response(request)
                        if name == 'repair' and (root/'work/target.txt').read_text() == original:
                            result.update(state='failure', exit_code=1, stdout='scripted failure', error_code='command_failed')
                        if name == 'command-refusal': result.update(state='refusal', execution='not_started', exit_code=None, error_code='refused')
                        if name == 'command-failure': result.update(state='failure', exit_code=2, error_code='command_failed')
                        if name == 'command-nonzero': result['exit_code'] = 4
                        if name == 'command-timeout': result.update(state='timeout', execution='unknown', exit_code=None, error_code='timeout')
                        if name == 'command-cancellation': result.update(state='cancellation', execution='not_started', exit_code=None, error_code='cancelled')
                        if name == 'command-identity': result['call_id'] = 'wrong'
                        if name == 'command-truncation': result.update(stdout='refusal', stdout_truncated=True)
                        if name == 'command-output-size': result['stdout'] = 'x'*65537
                        if name == 'command-type': result['stdout_truncated'] = 'false'
                        if name == 'command-transport':
                            time.sleep(2.3)
                        if name == 'command-malformed': result = 'malformed'
                    data = (result if isinstance(result, str) else json.dumps(result)).encode()
                    self.send_response(200)
                    self.send_header('Content-Length', str(len(data)))
                    self.end_headers()
                    self.wfile.write(data)
                except (BrokenPipeError, ConnectionResetError): pass
                except Exception as error:
                    errors.append(repr(error))
                    self.close_connection = True

        server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        thread = threading.Thread(target=server.serve_forever)
        thread.start()
        try:
            port = server.server_port
            args = ['coding-fixture', str(root), '--model', f'127.0.0.1:{port}', '--command', f'127.0.0.1:{port}', '--workspace', 'opaque-workspace', 'repair the fixture']
            command = [MO, 'run', 'examples/programs/agent/main.mo', '--'] if mode == 'interpreter' else [str(ROOT/'zig-out/mo-build/coding-fixture/coding-fixture')]
            evidence = invoke(command+args)
        finally:
            server.shutdown(); server.server_close(); thread.join(3)
        try:
            assert not errors, errors
            assert evidence['exit_code'] == expected_code, evidence
            events = [json.loads(line) for line in evidence['stdout'].splitlines()]
            assert events[-1]['event'] == 'terminal' and events[-1]['payload']['state'] == terminal, events
            assert all(e['schema'] == 'mo-coding-fixture-v1' and e['run_id'] == 'r_1' for e in events)
            commands = [r for r in requests if r['path'] == '/fixture/v1/command']
            models = [r for r in requests if r['path'] == '/complete']
            assert len(commands) == (2 if name == 'repair' else 1 if name.startswith('command-') else 0)
            if name == 'repair':
                assert (root/'work/target.txt').read_bytes() == b'fixed\n'
                assert [r['path'] for r in requests] == ['/complete','/fixture/v1/command','/complete','/complete','/complete','/fixture/v1/command','/complete']
            elif name == 'edit-unicode': assert (root/'work/target.txt').read_text() == 'a! / café\n'
            elif name.startswith('edit-'): assert (root/'work/target.txt').read_text() == original
            if name in REFUSALS:
                assert events[1]['event'] == 'tool' and events[1]['payload']['step']['refused'] is True, events[1]
                assert events[1]['payload']['result'] == dict(state='refusal', error_code=REFUSALS[name], execution='not_started'), events[1]
                assert events[-1]['payload']['state'] == 'done' and len(models) == 2
            if name == 'model-missing-usage': assert events[0]['payload']['usage'] == 'unknown' and events[-1]['payload']['tokens'] is None
            else: assert events[0]['payload']['usage'] == 'reported_synthetic'
            if name == 'steps': assert len(events) == 17 and len(models) == 8
            if name in ['tokens','context','model-missing-usage']: assert len(models) == 1
            if name == 'command-truncation':
                assert events[1]['payload']['result']['stdout_truncated'] is True
                assert events[1]['payload']['step']['refused'] is False
            if name == 'command-transport': assert events[1]['payload']['step']['took_ms'] >= 1000
            if name == 'command-nonzero': assert events[1]['payload']['result']['state'] == 'failure'
            if name == 'command-failure':
                result = events[1]['payload']['result']
                assert (result['state'], result['exit_code'], result['error_code'], result['execution']) == ('failure', 2, 'command_failed', 'completed'), result
                assert events[1]['payload']['step']['refused'] is False and len(models) == 2
            evidence.update(passed=True)
        except Exception as error:
            evidence.update(passed=False, assertion=repr(error))
        evidence.update(case=name, mode=mode, requests=requests, listener_closed=server.fileno()==-1)
        # Keep bounded evidence: payloads can be large; request sizes and recorded counts suffice.
        for request in evidence['requests']:
            request['body_bytes'] = len(json.dumps(request['body']).encode())
            request['recorded_count'] = len(request.pop('recorded'))
            if request['path'] == '/complete': request['body'] = {'tools': request['body']['tools'], 'transcript_count':len(request['body']['transcript'])}
        print(json.dumps(evidence), flush=True)
        return evidence['passed']


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('mode', choices=['interpreter','compiled'])
    parser.add_argument('--only', choices=CASES)
    args = parser.parse_args()
    results = [case(name, args.mode) for name in ([args.only] if args.only else CASES)]
    raise SystemExit(0 if all(results) else 1)
