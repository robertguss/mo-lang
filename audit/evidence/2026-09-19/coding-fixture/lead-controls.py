"""Independent malformed command controls against the integrated Mo CLI."""
import http.server
import importlib.util
import json
from pathlib import Path
import tempfile
import threading

ROOT = Path(__file__).resolve().parents[4]
spec = importlib.util.spec_from_file_location('fixture_runner', ROOT / 'examples/programs/agent/tests/coding-fixture-v1/run.py')
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)
failures = 0
for mode in ['interpreter', 'compiled']:
    for name in ['failure-with-zero-exit', 'boolean-exit', 'string-elapsed']:
        with tempfile.TemporaryDirectory(prefix='mo-lead-command-') as tmp:
            root = Path(tmp)
            (root / 'work').mkdir()
            calls, errors = [], []

            class Handler(http.server.BaseHTTPRequestHandler):
                def setup(self):
                    super().setup()
                    self.connection.settimeout(3)

                def log_message(self, *_):
                    pass

                def do_POST(self):
                    try:
                        body = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
                        log = next((root / 'runs').glob('*.log'))
                        stored = [json.loads(x)['step'] for x in log.read_text().splitlines() if 'step' in json.loads(x)]
                        calls.append({'path': self.path, 'stored_count': len(stored)})
                        if self.path == '/complete':
                            assert body['transcript'] == stored
                            result = {'tool': 'command', 'args': {'command': 'inert-lead-control'}, 'tokens': 11}
                        else:
                            assert self.path == '/fixture/v1/command' and len(stored) == 1
                            assert stored[0]['kind'] == 'model'
                            result = {'version': 1, 'run_id': body['run_id'], 'call_id': body['call_id'],
                                      'workspace_id': body['workspace_id'], 'state': 'success', 'exit_code': 0,
                                      'stdout': '', 'stderr': '', 'stdout_truncated': False, 'stderr_truncated': False,
                                      'elapsed_ms': 1, 'error_code': 'none', 'execution': 'completed'}
                            if name == 'failure-with-zero-exit':
                                result.update(state='failure', error_code='command_failed')
                            elif name == 'boolean-exit':
                                result['exit_code'] = True
                            else:
                                result['elapsed_ms'] = '1'
                        payload = json.dumps(result).encode()
                        self.send_response(200)
                        self.send_header('Content-Length', str(len(payload)))
                        self.end_headers()
                        self.wfile.write(payload)
                    except Exception as error:
                        errors.append(repr(error))
                        self.close_connection = True

            server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
            thread = threading.Thread(target=server.serve_forever)
            thread.start()
            args = ['coding-fixture', str(root), '--model', f'127.0.0.1:{server.server_port}',
                    '--command', f'127.0.0.1:{server.server_port}', '--workspace', 'lead-extra', 'inspect a malformed command reply']
            command = [runner.MO, 'run', 'examples/programs/agent/main.mo', '--'] if mode == 'interpreter' else [str(ROOT / 'zig-out/mo-build/coding-fixture/coding-fixture')]
            try:
                result = runner.invoke(command + args, 55)
            finally:
                server.shutdown()
                server.server_close()
                thread.join(3)
            try:
                assert not errors and not thread.is_alive() and server.fileno() == -1, errors
                assert result['exit_code'] == 3, result
                events = [json.loads(line) for line in result['stdout'].splitlines()]
                assert [e['event'] for e in events] == ['model', 'tool', 'terminal'], events
                assert events[0]['payload']['tokens'] == 11
                assert events[1]['payload']['result'] == {'state': 'failure', 'error_code': 'invalid_response', 'execution': 'unknown'}
                assert events[2]['payload']['state'] == 'failed'
                assert calls == [{'path': '/complete', 'stored_count': 0}, {'path': '/fixture/v1/command', 'stored_count': 1}], calls
                result['passed'] = True
            except Exception as error:
                failures += 1
                result.update(passed=False, assertion=repr(error))
            print(json.dumps({'case': name, 'mode': mode, 'requests': calls, 'server_closed': server.fileno() == -1, **result}), flush=True)
raise SystemExit(int(failures != 0))
