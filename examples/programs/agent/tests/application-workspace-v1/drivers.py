"""Real-socket driver controls in one runtime per attempt: near-expiry dispatch, the outer
deadline's report reserve, the poller's answers and scheduling, and cancellation during command
collection. Usage: drivers.py interpreter|native ATTEMPT [--only case,case]"""
import json
import os
from pathlib import Path
import sys
import tempfile
import time

from common import HERE, MO, ROOT, Attempt, invoke, trimmed
import fake_bridge as fb
from matrix import PROFILE, done, tool, steps_in

MARGIN = PROFILE['candidate_margin_ms']

DRIVER = HERE / 'driver.mo'
NATIVE = ROOT / 'zig-out/mo-build/application-driver/application-driver'


def near(ms, size=100):
    def run(env):
        line = env.drive(['near', env.config, ms, size])
        return line, dict()
    return run


def expect_near(refused, cap=None, completed=False):
    """A clamped command's timeout leaves the collection margin before what remained, so the
    bridge's reply, which comes after the timeout, can still arrive."""
    def check(env, line):
        reqs = env.bridge.requests
        found = dict(parsed='output' in line)
        output = json.loads(line.get('output', '{}'))
        if refused:
            found.update(refused=output.get('error') == 'deadline', no_http=not reqs)
        else:
            timeout = reqs[0]['args']['timeout_ms'] if reqs else -1
            found.update(one_request=len(reqs) == 1, floor=timeout >= 500,
                         within_margin=timeout <= line.get('before_ms', -1) - MARGIN,
                         capped=cap is None or timeout == cap)
        if completed:
            found.update(received=output.get('state') == 'success' and output.get('execution') == 'completed')
        return found
    return check


def collected(seconds):
    """The bridge answers a command this long after its timeout, as the service does once it has
    collected the command and proved its cleanup (measured 0.5 to 1.4 s)."""
    return lambda req, n: fb.success(req) + (req['args']['timeout_ms'] / 1000 + seconds,)


def launch(ms, goal='repair'):
    def run(env):
        started = time.monotonic()
        line = env.drive(['launch', env.config, env.root, env.model.port, ms] + goal.split())
        return line, dict(elapsed_ms=round((time.monotonic() - started) * 1000))
    return run


def report_of(line):
    rows = []
    for text in line.get('output', '').splitlines():
        try:
            rows.append(json.loads(text))
        except ValueError:
            rows.append(dict(unparsed=text))
    return rows


def event(rows, name):
    return [r['payload'] for r in rows if r.get('event') == name]


def answered_once(line):
    polls = line.get('polls', [-1, -2])
    return dict(answered_once=line.get('answers') == 1, stopped_polling=polls[0] == polls[1] >= 0)


class Case:
    def __init__(self, run, check, replies=(), script=None, setup=None, model_delays=None):
        self.__dict__.update(locals())


CASES = {
    # A command refused below the 500 ms minimum sends nothing.
    'near-refused': Case(near(499), expect_near(True)),
    # Or when what remains less the collection margin is below it.
    'near-margin-refused': Case(near(MARGIN + 400), expect_near(True)),
    # A command near expiry is sent with a timeout no longer than what remained less the margin.
    'near-sent': Case(near(MARGIN + 1500), expect_near(False)),
    # End to end v1's defect D1: the clamped command's reply, 1.4 s after its timeout, arrives,
    # and its execution is known.
    'near-collected': Case(near(MARGIN + 3000), expect_near(False, completed=True), script=collected(1.4)),
    # The largest command request: encoding first, the timeout taken afterwards.
    'near-largest': Case(near(MARGIN + 3000, 851000), expect_near(False)),
    # A command far from expiry is capped at the 120 s candidate allowance.
    'near-capped': Case(near(600000), expect_near(False, 120000)),
    # An outer deadline without room for the report reserve refuses before any request.
    'reserve-exhausted': Case(launch(14000), lambda env, line: dict(
        error=[p.get('error') for p in event(report_of(line), 'reporting_error')] == ['work_deadline'],
        no_requests=not env.bridge.requests and not env.model.requests, **answered_once(line)),
        replies=[done()]),
    # Work gets the outer deadline less 15 s; a command outlasting it is clamped to that less the
    # collection margin, then reported inside the outer deadline.
    'reserve-inside': Case(launch(15000 + MARGIN + 5000), lambda env, line, extra: dict(
        terminal=[p.get('error') for p in event(report_of(line), 'terminal')] == ['uncertain_or_terminal_tool'],
        clamped=bool(env.bridge.requests) and 500 <= env.bridge.requests[0]['args']['timeout_ms'] <= 5000,
        inside_outer=extra['elapsed_ms'] < 15000 + MARGIN + 5000, **answered_once(line)),
        replies=[tool('command', command='slow'), done()],
        script=lambda req, n: fb.success(req) + (MARGIN / 1000 + 8.0,)),
    # Normal completion answers once and stops scheduling.
    'poller-normal': Case(launch(60000), lambda env, line: dict(
        done=[p.get('state') for p in event(report_of(line), 'terminal')] == ['done'], **answered_once(line)),
        replies=[done('ok')]),
    # A startup error answers once and never schedules a poll.
    'poller-startup-error': Case(launch(60000), lambda env, line: dict(
        error=[p.get('error') for p in event(report_of(line), 'reporting_error')] == ['work_missing'],
        never_polled=line.get('polls') == [0, 0], answered_once=line.get('answers') == 1),
        replies=[done()], setup=lambda root: (root / 'work').rmdir()),
    # A watch that reaches its deadline answers once, with a reporting error, and stops.
    'poller-deadline': Case(lambda env: (env.drive(['unbegun', env.config, env.root, env.model.port, 1500, 'g']), {}),
        lambda env, line: dict(
            error=[p.get('error') for p in event(report_of(line), 'reporting_error')] == ['report_deadline'],
            no_requests=not env.bridge.requests and not env.model.requests, **answered_once(line)),
        replies=[done()]),
    # Cancellation during command collection: the recorded call keeps its usage, the terminal
    # total is unknown, nothing is dispatched after it, and the log holds still after the report.
    'cancel-collection': Case(lambda env: (env.drive(['cancel', env.config, env.root, env.model.port, 500, 'g']), {}),
        lambda env, line: dict(
            cancelled=line.get('cancelled') is True, stable=line.get('stable') is True,
            stopped=line.get('stopped') is True,
            terminal=event(report_of(line), 'terminal') == [dict(state='cancelled', result=None, error=None, usage='unknown', tokens=None)],
            call_usage=[p.get('tokens') for p in event(report_of(line), 'model')] == [17],
            no_later_dispatch=len(env.model.requests) == 1 and len(env.bridge.requests) == 1),
        replies=[tool('command', tokens=17, command='slow'), done()],
        script=lambda req, n: fb.success(req) + (1.5,)),
    # A Book holding a transcript of exactly the report cap is reported whole; one byte more is a
    # proved reporting error, not a report.
    'report-at-cap': Case(lambda env: (env.drive(['oversized', env.config, env.root, env.model.port, 0, 'g']), {}),
        lambda env, line: dict(
            size=line.get('transcript_bytes') == PROFILE['report_bytes'], code=line.get('code') == 0,
            terminal=json.loads(line.get('last') or '{}').get('payload', {}).get('state') == 'done',
            no_bridge=not env.bridge.requests),
        replies=[done('ok')]),
    'report-past-cap': Case(lambda env: (env.drive(['oversized', env.config, env.root, env.model.port, 1, 'g']), {}),
        lambda env, line: dict(
            size=line.get('transcript_bytes') == PROFILE['report_bytes'] + 1, code=line.get('code') == 3,
            refused=json.loads(line.get('last') or '{}').get('payload') == dict(error='transcript_too_large', persistence='proved'),
            one_line=line.get('lines') == 1, no_bridge=not env.bridge.requests),
        replies=[done('ok')]),
}


class Env:
    def __init__(self, runtime, tmp, spec):
        self.runtime = runtime
        self.tmp = Path(tmp)
        root = self.tmp / 'root'
        (root / 'work').mkdir(parents=True)
        if spec.setup:
            spec.setup(root)
        self.root = str(root)
        log = root / 'runs/r_1.log'
        self.bridge = fb.Bridge(spec.script, observe=lambda: steps_in(log))
        self.model = fb.Model(spec.replies, spec.model_delays, observe=lambda: steps_in(log))
        self.config = str(self.bridge.write_config(self.tmp / 'private/bridge.json'))
        self.rows = []

    def drive(self, args):
        prefix = [MO, 'run', str(DRIVER), '--'] if self.runtime == 'interpreter' else [str(NATIVE)]
        row = invoke(prefix + [str(a) for a in args], 150, cwd=self.tmp)
        self.rows.append(row)
        lines = [l for l in row['stdout'].splitlines() if l.startswith('{')]
        try:
            return json.loads(lines[-1]) if lines else {}
        except ValueError:
            return {}

    def close(self):
        self.bridge.close()
        self.model.close()


def run_case(name, spec, runtime):
    with tempfile.TemporaryDirectory(prefix='mo-app-driver-') as tmp:
        env = Env(runtime, tmp, spec)
        try:
            line, extra = spec.run(env)
        finally:
            env.close()
        row = env.rows[-1]
        token = env.bridge.token
        checks = dict(exit_code=row['exit_code'] == 0, requests_valid=not env.bridge.errors,
                      token_absent=token not in row['stdout'] + row['stderr'])
        try:
            found = spec.check(env, line, extra) if spec.check.__code__.co_argcount == 3 else spec.check(env, line)
            checks.update(found)
        except Exception as exc:
            checks['case_check'] = False
            row = dict(row, check_error=repr(exc))
        row = dict(row, case=name, runtime=runtime, checks=checks, line={k: v for k, v in line.items() if k != 'output'},
                   report=report_of(line)[-3:], extra=extra,
                   bridge_requests=[{k: r.get(k) for k in ('operation', 'call_id', 'args', 'bytes', 'observed', 'answered')} for r in env.bridge.requests],
                   model_requests=[{k: r.get(k) for k in ('transcript', 'observed')} for r in env.model.requests])
        return trimmed(row, all(checks.values()))


def main():
    runtime, attempt_name = sys.argv[1], sys.argv[2]
    only = sys.argv[sys.argv.index('--only') + 1].split(',') if '--only' in sys.argv else list(CASES)
    unknown = [n for n in only if n not in CASES]
    if runtime not in ('interpreter', 'native') or unknown or len(set(only)) != len(only):
        raise SystemExit(f'bad runtime or cases: {runtime} {unknown}')
    attempt = Attempt(attempt_name)
    if runtime == 'native':
        built = invoke([MO, 'build', str(DRIVER), '-o', 'application-driver'], 600)
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
