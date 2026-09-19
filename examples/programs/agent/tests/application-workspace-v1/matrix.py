"""Named application-workspace HTTP cases through the real CLI, in one runtime per attempt.
Usage: matrix.py interpreter|native ATTEMPT [--only case,case]

Every case runs the actual agent executable against a scripted loopback model and the strict
bridge double, from a fresh disposable root whose work/ holds conflicting operator canaries,
with the private configuration in a separate 0700 directory. Shared checks on every case: no
capability in stdout, stderr, model requests, the Book or work/; every bridge request valid under
the accepted protocol; the Book on disk holding exactly the steps before each model and tool
dispatch; work/ unchanged; every output line of the versioned schema."""
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile

from common import AGENT, HERE, MO, ROOT, Attempt, invoke, trimmed
import fake_bridge as fb

SCHEMA = 'mo-application-workspace-v1'
MAIN = AGENT / 'main.mo'
NATIVE = ROOT / 'zig-out/mo-build/application-agent/application-agent'


def tool(name, tokens=1, **args):
    return dict(tool=name, args=args, tokens=tokens)


def done(text='done', tokens=1):
    return dict(done=text, tokens=tokens)


def steps_in(log):
    """(count, last number) of step lines the Book's log holds now."""
    try:
        numbers = [json.loads(line)['step']['n'] for line in log.read_text().splitlines()
                   if '"step":' in line and line.endswith('}')]
    except (OSError, ValueError, KeyError):
        return None
    return [len(numbers), numbers[-1] if numbers else 0]


def reply(req, state='success', execution='completed', error=None, result=None, status=200, **fields):
    body = fb.envelope(req, state=state, execution=execution, error=error, result=result)
    body.update(fields)
    return status, body


def command_result(exit_code=0, stdout='', stderr='', **more):
    value = dict(exit_code=exit_code, signal=None, execution_valid=True, stdout=stdout, stderr=stderr,
                 encoding='utf-8', truncated=False, elapsed_ms=40)
    value.update(more)
    return value


def by_op(**answers):
    """A script choosing per operation (and per nth request, as op#n), else success."""
    def script(req, n):
        pick = answers.get(f"{req['operation']}#{n}", answers.get(req['operation']))
        return pick(req) if pick else fb.success(req)
    return script


class Case:
    def __init__(self, replies, script=None, exit_code=0, seconds=120, config=None, raw_config=None,
                 goal='repair the workspace', setup=None, check=None, model_delays=None, bridge=True,
                 run_id='r_1', on_model=None):
        self.__dict__.update(locals())


def invalid(req):
    return reply(req, result=dict(text='x', truncated=False), extra=1)


CASES = {}


def case(name, **kwargs):
    CASES[name] = Case(**kwargs)


# 1. Every tool routed remotely, in order, with the local canaries untouched.
case('six-tools', replies=[tool('list_files', path='.'), tool('read_file', path='a.txt'),
                           tool('search', query='text'), tool('write_file', path='new.txt', text='hello'),
                           tool('exact_edit', path='a.txt', old_text='remote', new_text='edited'),
                           tool('command', command='make test'), done('all six')],
     check=lambda c: dict(
         operations=[r['operation'] for r in c.bridge.requests] == ['list_files', 'read_file', 'search', 'write_file', 'exact_edit', 'command'],
         call_ids=[r['call_id'] for r in c.bridge.requests] == ['2', '4', '6', '8', '10', '12'],
         args_unchanged=c.bridge.requests[3]['args'] == {'path': 'new.txt', 'text': 'hello'},
         remote_text=any('remote text' in s for s in c.tool_results()) and not any('LOCAL CANARY' in s for s in c.tool_results()),
         no_local_write=not (c.root / 'work/new.txt').exists(),
         candidate_timeout=500 <= c.bridge.requests[5]['args']['timeout_ms'] <= 120000,
         terminal=c.terminal() == ('done', 'all six', None),
         tokens=c.terminal_payload().get('tokens') == 7 and c.terminal_payload().get('usage') == 'reported_synthetic',
         profile=c.profile() == dict(PROFILE)))

# 2. A failed command with completed execution is repair feedback, then read, edit, command, answer.
case('repair', replies=[tool('command', command='make test'), tool('read_file', path='target.txt'),
                        tool('exact_edit', path='target.txt', old_text='broken', new_text='fixed'),
                        tool('command', command='make test'), done('repaired')],
     script=by_op(**{'command#1': lambda req: reply(req, state='failure', result=command_result(1, '', 'FAIL\n')),
                     'read_file': lambda req: reply(req, result=dict(text='broken\n', truncated=False))}),
     check=lambda c: dict(
         sequence=[r['operation'] for r in c.bridge.requests] == ['command', 'read_file', 'exact_edit', 'command'],
         failed_then_continued=len(c.model.requests) == 5,
         terminal=c.terminal() == ('done', 'repaired', None)))

# 3. Distinct waits: a file call within 2 s and a command answered after 3 s both complete.
case('waits', replies=[tool('read_file', path='a.txt'), tool('command', command='slow'), done()],
     script=by_op(read_file=lambda req: fb.success(req) + (1.2,), command=lambda req: fb.success(req) + (3.0,)),
     check=lambda c: dict(terminal=c.terminal()[0] == 'done',
                          command_timeout=500 <= c.bridge.requests[1]['args']['timeout_ms'] <= 120000))

# 4. A file call past its 2 s wait is unknown and stops dispatch; the model is not asked again.
case('file-wait', replies=[tool('read_file', path='a.txt'), done()], exit_code=3,
     script=by_op(read_file=lambda req: fb.success(req) + (2.6,)),
     check=lambda c: dict(stopped=c.stopped(), model_once=len(c.model.requests) == 1,
                          unknown=c.tool_fields(0).get('execution') == 'unknown'))


def refused_before_http(**more):
    return lambda c: dict(no_http=not c.bridge.requests, terminal=c.terminal()[0] == 'done', **more)


# 5. Grants, exact arguments and model-supplied timeouts are refused before any request.
case('arguments', replies=[tool('read_file', path='a.txt', extra='x'),
                           tool('command', command='make', timeout_ms='900000'),
                           tool('write_file', path='a.txt'), tool('list_files', path='.', query='q'), done()],
     check=lambda c: dict(no_http=not c.bridge.requests, terminal=c.terminal()[0] == 'done',
                          refusals=[c.tool_fields(i).get('error') for i in range(4)] == ['arguments'] * 4,
                          recorded_refused=all(c.tool_step(i).get('refused') is True for i in range(4)),
                          model_args_unchanged=c.tool_step(1).get('args') == {'command': 'make', 'timeout_ms': '900000'}))

# 6. An encoded request over the cap is refused before HTTP; the next request then exceeds the
# context bound, and a transcript over the report cap is a proved reporting error, not a report.
case('request-bound', replies=[tool('write_file', path='big.txt', text='y' * 851968)], exit_code=3,
     check=lambda c: dict(no_http=not c.bridge.requests, error=c.error() == 'transcript_too_large',
                          refusal=any('request_too_large' in json.loads(l).get('step', {}).get('result', '')
                                      for l in c.log_lines() if '"step":' in l),
                          over_context='"context_bytes"' in c.log_lines()[-1]))
# A transcript just under the report cap is still reported in full; one over it is an error.
case('report-over', replies=[tool('write_file', path='big.txt', text='y' * 350000)], exit_code=3,
     check=lambda c: dict(sent=len(c.bridge.requests) == 1, error=c.error() == 'transcript_too_large'))
case('report-bound', replies=[tool('write_file', path='big.txt', text='y' * 100000)], exit_code=3,
     check=lambda c: dict(sent=len(c.bridge.requests) == 1,
                          over_context=c.terminal() == ('over_budget', None, 'context_bytes'),
                          reported=len(c.events('tool')) == 1 and len(c.events('model')) == 1))


def stops(name, answer, expect=None, replies=None):
    def check(c):
        found = dict(stopped=c.stopped(), model_once=len(c.model.requests) == 1,
                     one_request=len(c.bridge.requests) == 1)
        if expect:
            found.update(expect(c))
        return found
    case(name, replies=replies or [tool('read_file', path='a.txt'), done()], exit_code=3,
         script=lambda req, n: answer(req), check=check)


def unknown_output(c):
    return dict(invalid=c.tool_fields(0) == dict(adapter=SCHEMA, state='failure', execution='unknown', error='invalid_response'))


# 7. Response schema, identity, status and number negatives are unknown execution and stop.
stops('schema-extra-key', lambda req: reply(req, result=dict(text='x', truncated=False), extra=1), unknown_output)
stops('schema-duplicate-key', lambda req: (200, fb.protocol.encode(fb.envelope(req, result=dict(text='x', truncated=False)))[:-1] + b',"error":null}'), unknown_output)
stops('schema-float', lambda req: (200, fb.protocol.encode(fb.envelope(req, result=command_result(0))).replace(b'"elapsed_ms":40', b'"elapsed_ms":40.0')), unknown_output, replies=[tool('command', command='t'), done()])
stops('schema-call-id', lambda req: reply(req, call_id='99', result=dict(text='x', truncated=False)), unknown_output)
stops('schema-workspace', lambda req: reply(req, workspace_id='f' * 32, result=dict(text='x', truncated=False)), unknown_output)
stops('status-busy-500', lambda req: (500, fb.envelope(req, accepted=False, state='refusal', execution='not_started', error='busy')), unknown_output)
stops('success-exit-1', lambda req: reply(req, result=command_result(1)), unknown_output, replies=[tool('command', command='t'), done()])
stops('success-null-streams', lambda req: reply(req, result=command_result(0, None, None)), unknown_output, replies=[tool('command', command='t'), done()])
stops('response-bound', lambda req: reply(req, result=dict(text='z' * 524288, truncated=False)), unknown_output)
# 8. Legitimate stopping outcomes are kept verbatim: pre-admission refusal, 504, owner_unknown.
stops('unauthorized-401', lambda req: (401, dict(version=fb.protocol.VERSION, run_id=None, workspace_id=None, call_id=None, accepted=False, state='refusal', execution='not_started', error='unauthorized', result=None)),
      lambda c: dict(kept=c.tool_fields(0).get('execution') == 'not_started' and c.tool_fields(0).get('error') == 'unauthorized'))
stops('response-timeout-504', lambda req: (504, fb.envelope(req, state='timeout', execution='unknown', error='response_timeout')),
      lambda c: dict(kept=c.tool_fields(0).get('error') == 'response_timeout'))
stops('owner-unknown', lambda req: reply(req, state='failure', execution='unknown', error='owner_unknown'),
      lambda c: dict(kept=c.tool_fields(0).get('error') == 'owner_unknown'))
stops('lost-response', lambda req: (200, None), lambda c: dict(transport=c.tool_fields(0).get('execution') == 'unknown'))

# 9. Completed refusals and completed output-encoding failures are feedback and continue.
case('completed-outcomes', replies=[tool('read_file', path='../x'), tool('command', command='bin'), done()],
     script=by_op(read_file=lambda req: reply(req, state='refusal', execution='completed', error='invalid_path'),
                  command=lambda req: reply(req, state='failure', error='output_encoding', result=command_result(3, None, None))),
     check=lambda c: dict(continued=len(c.model.requests) == 3, terminal=c.terminal()[0] == 'done',
                          refused=c.tool_step(0).get('refused') is True))

# 10. Configuration negatives: nothing is read into a Book, no model or bridge request.
for name, raw in {'config-duplicate': lambda b: json.dumps(b.config())[:-1] + ', "port": 1}',
                  'config-float-port': lambda b: json.dumps(b.config()).replace(f'"port": {b.port}', f'"port": {b.port}.0'),
                  'config-extra-key': lambda b: json.dumps(b.config(extra=1)),
                  'config-short-token': lambda b: json.dumps(b.config(token='ab' * 31)),
                  'config-oversized': lambda b: json.dumps(b.config()) + ' ' * 4096,
                  'config-missing': None}.items():
    case(name, replies=[done()], raw_config=raw, exit_code=3,
         check=lambda c, name=name: dict(no_requests=not c.bridge.requests and not c.model.requests,
                                         no_book=not (c.root / 'runs').exists(),
                                         error=c.error() == {'config-duplicate': 'config_json', 'config-float-port': 'config_json',
                                                             'config-extra-key': 'config_keys', 'config-short-token': 'config_token',
                                                             'config-oversized': 'config_size', 'config-missing': 'config_unreadable'}[name]))

# 11. The Book's run must be the bridge's external run, before any request.
case('run-binding', replies=[done()], run_id='r_2', exit_code=3,
     check=lambda c: dict(no_requests=not c.bridge.requests and not c.model.requests, error=c.error() == 'run_binding'))


# 12. A root that is not fresh is refused before the Book opens, and left as it was.
def fresh_setup(kind):
    def setup(root):
        if kind == 'work-missing':
            (root / 'work').rename(root / 'elsewhere')
        else:
            (root / 'runs').mkdir()
            (root / 'runs' / ('r_1.log' if kind == 'empty-log' else 'notes.txt')).write_text('' if kind == 'empty-log' else 'x\n')
    return setup


for kind, why in {'empty-log': 'root_not_fresh', 'unrecognized': 'root_not_fresh', 'work-missing': 'work_missing'}.items():
    case('fresh-' + kind, replies=[done()], exit_code=3, setup=fresh_setup(kind),
         check=lambda c, why=why: dict(no_requests=not c.bridge.requests and not c.model.requests, error=c.error() == why))

# 13. A lost write acknowledgement: the log turns read-only as the first model call arrives, so the
# model step and the end are both unrecorded; Run stops, the Book stays running, and the report
# is an uncertain reporting error with nothing dispatched to the bridge.
def read_only_log(root):
    (root / 'runs/r_1.log').chmod(0o444)


case('lost-ack', replies=[tool('read_file', path='a.txt'), done()], exit_code=3, on_model=read_only_log,
     check=lambda c: dict(no_http=not c.bridge.requests, model_once=len(c.model.requests) == 1,
                          unsettled=c.error() == 'book_unsettled',
                          uncertain=c.events('reporting_error')[0]['payload'].get('persistence') == 'uncertain',
                          log_unchanged=len(c.log_lines()) == 1))

PROFILE = dict(steps=16, tokens=4096, wall_ms=900000, retries=0, tool_ms=2000,
               grants=['list_files', 'read_file', 'search', 'write_file', 'exact_edit', 'command'],
               report_reserve_ms=15000, model_wait_ms=2000, file_wait_ms=2000, command_wait_ms=300000,
               candidate_ms=120000, candidate_floor_ms=500, request_bytes=851968, response_bytes=524288,
               config_bytes=4096, report_bytes=262144, wire='mo-workspace-http-v1')


class Context:
    def __init__(self, root, bridge, model, row):
        self.root, self.bridge, self.model, self.row = root, bridge, model, row
        self.lines = []
        for line in row['stdout'].splitlines():
            try:
                self.lines.append(json.loads(line))
            except ValueError:
                self.lines.append(dict(unparsed=line))

    def log_lines(self):
        log = self.root / 'runs/r_1.log'
        return log.read_text().splitlines() if log.exists() else []

    def events(self, name):
        return [l for l in self.lines if l.get('event') == name]

    def profile(self):
        found = self.events('profile')
        return found[0]['payload'] if found else None

    def terminal_payload(self):
        found = self.events('terminal')
        return found[-1]['payload'] if found else {}

    def terminal(self):
        p = self.terminal_payload()
        return (p.get('state'), p.get('result'), p.get('error'))

    def error(self):
        found = self.events('reporting_error')
        return found[0]['payload'].get('error') if found else None

    def tool_step(self, i):
        tools = self.events('tool')
        return tools[i]['payload']['step'] if i < len(tools) else {}

    def tool_fields(self, i):
        tools = self.events('tool')
        result = tools[i]['payload']['result'] if i < len(tools) else None
        return result if isinstance(result, dict) else {}

    def tool_results(self):
        return [json.dumps(t['payload']['result']) for t in self.events('tool')]

    def stopped(self):
        return self.terminal() == ('failed', None, 'uncertain_or_terminal_tool')


def tree(path):
    return {str(p.relative_to(path)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(path.rglob('*')) if p.is_file()} if path.exists() else None


def prefix_checks(bridge, model):
    """Each dispatch arrived when the log held exactly the steps before it, in order."""
    rows = [(r['arrived'], r['transcript'] + 1, r['observed']) for r in model.requests if 'transcript' in r]
    rows += [(r['arrived'], int(r['call_id']), r['observed']) for r in bridge.requests]
    rows.sort()
    ok = all(observed is not None and observed == [n - 1, n - 1] or (n == 1 and observed in (None, [0, 0]))
             for _, n, observed in rows)
    ordered = [n for _, n, _ in rows] == sorted(n for _, n, _ in rows)
    return dict(book_prefix=ok, dispatch_order=ordered)


def run_case(name, spec, runtime):
    with tempfile.TemporaryDirectory(prefix='mo-app-case-') as tmp:
        tmp = Path(tmp)
        root = tmp / 'root'
        (root / 'work').mkdir(parents=True)
        (root / 'work/a.txt').write_text('LOCAL CANARY remote text is not here\n')
        (root / 'work/target.txt').write_text('LOCAL CANARY broken\n')
        if spec.setup:
            spec.setup(root)
        placeholders = tree(root / 'work' if (root / 'work').exists() else root / 'elsewhere')
        runs_before = tree(root / 'runs')
        log = root / 'runs/r_1.log'
        bridge = fb.Bridge(spec.script, run_id=spec.run_id, observe=lambda: steps_in(log))
        def observe_model():
            seen = steps_in(log)
            if spec.on_model:
                spec.on_model(root)
            return seen
        model = fb.Model(spec.replies, spec.model_delays, observe=observe_model)
        config = tmp / 'private/bridge.json'
        if spec.raw_config is None and name != 'config-missing':
            bridge.write_config(config)
        elif spec.raw_config is not None:
            config.parent.mkdir(mode=0o700)
            config.write_text(spec.raw_config(bridge))
            config.chmod(0o600)
        prefix = [MO, 'run', str(MAIN), '--'] if runtime == 'interpreter' else [str(NATIVE)]
        args = prefix + ['application-workspace', str(root), '--model', f'127.0.0.1:{model.port}',
                         '--config', str(config)] + spec.goal.split()
        row = invoke(args, spec.seconds, cwd=tmp)
        bridge.close()
        model.close()
        c = Context(root, bridge, model, row)
        token = bridge.token
        logged = log.read_text() if log.exists() else ''
        work = root / 'work' if (root / 'work').exists() else root / 'elsewhere'
        checks = dict(
            exit_code=row['exit_code'] == spec.exit_code,
            schema=bool(c.lines) and all(l.get('schema') == SCHEMA for l in c.lines),
            token_absent=all(token not in text for text in [row['stdout'], row['stderr'], logged, ' '.join(args)]
                             + [r['raw'].decode('latin-1') for r in model.requests if 'raw' in r]
                             + [p.read_text(errors='replace') for p in work.rglob('*') if p.is_file()]),
            requests_valid=not bridge.errors,
            placeholders_unchanged=tree(work) == placeholders,
            runs_unchanged=spec.setup is None or tree(root / 'runs') == runs_before,
            **prefix_checks(bridge, model))
        try:
            checks.update(spec.check(c))
        except Exception as exc:
            checks['case_check'] = False
            row['check_error'] = repr(exc)
        row = dict(row, case=name, runtime=runtime, checks=checks,
                   bridge_requests=[{k: r.get(k) for k in ('operation', 'call_id', 'args', 'bytes', 'observed', 'answered', 'header_names')} for r in bridge.requests],
                   bridge_errors=[r.get('error') for r in bridge.errors],
                   model_requests=[{k: r.get(k) for k in ('transcript', 'bytes', 'observed', 'run')} for r in model.requests])
        return trimmed(row, all(checks.values()))


def main():
    runtime, attempt_name = sys.argv[1], sys.argv[2]
    only = sys.argv[sys.argv.index('--only') + 1].split(',') if '--only' in sys.argv else list(CASES)
    unknown = [n for n in only if n not in CASES]
    if runtime not in ('interpreter', 'native') or unknown or len(set(only)) != len(only):
        raise SystemExit(f'bad runtime or cases: {runtime} {unknown}')
    attempt = Attempt(attempt_name)
    if runtime == 'native':
        built = invoke([MO, 'build', str(MAIN), '-o', 'application-agent'], 600)
        magic = NATIVE.read_bytes()[:4] if NATIVE.is_file() else b''
        ok = built['exit_code'] == 0 and os.access(NATIVE, os.X_OK) and magic in (b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf', b'\x7fELF')
        attempt.record(trimmed(dict(built, check='native-executable', executable=str(NATIVE.relative_to(ROOT))), ok))
        if not ok:
            sys.exit(1)
    for name in only:
        attempt.record(run_case(name, CASES[name], runtime))
    sys.exit(int(attempt.failed))


if __name__ == '__main__':
    main()
