"""The Mo agent end to end on mo-executor-r01: a scripted loopback model, the real workspace
service over the application policy, real containers, and the protected verdict.

Usage: driver.py PART RUNTIME ATTEMPT [--only case,case]
  PART     readiness | smoke | logstat | negatives
  RUNTIME  interpreter | native (readiness takes 'none': it runs no agent)

Each case prepares a candidate tree, starts the real service for it, writes the private bridge
configuration (0600 in a 0700 directory, outside the Book and the candidate), starts the scripted
model and runs `agent application-workspace` under a guard, then freezes, runs the protected
verifier, closes (or kills the owner and runs cleanup-only recovery) and proves on the machine that
the workspace is gone. Per tool call it records admission, execution, reply (produced by the
service versus received in the Book) and cleanup, from the service's journal and the agent's Book
independently. Rows go to evidence/ATTEMPT.jsonl; small per-case files to evidence/ATTEMPT/."""
import base64
import gzip
import hashlib
import json
import os
from pathlib import Path
import secrets
import shutil
import sys
import threading
import time

import e2e
from e2e import AGENT, EVIDENCE, MO, SCHEMA, WORK, Attempt, Model, done, invoke, steps_in, summary, tool
import logstat_case
import prepare
import service
from cases import require_absent, workspace_absence

MAIN = AGENT / 'main.mo'


# ---------------------------------------------------------------- agent executables

def agent_prefix(runtime, attempt_dir, attempt):
    if runtime == 'interpreter':
        return [MO, 'run', str(MAIN), '--']
    build = attempt_dir / 'native'
    build.mkdir(parents=True)
    row = invoke([MO, 'build', str(MAIN), '-o', 'e2e-agent'], 900, cwd=build)
    binary = build / 'zig-out/mo-build/e2e-agent/e2e-agent'
    magic = binary.read_bytes()[:4] if binary.is_file() else b''
    ok = row['exit_code'] == 0 and os.access(binary, os.X_OK) and magic in (b'\xcf\xfa\xed\xfe', b'\x7fELF')
    attempt.record(dict(part='native-build', command=row['command'][3:], exit_code=row['exit_code'],
                        elapsed_s=row['elapsed_s'], summary=summary(row['stdout'] + row['stderr']),
                        passed=ok, checks=dict(executable=ok)))
    if not ok:
        raise SystemExit('native agent did not build')
    return [str(binary)]


# ---------------------------------------------------------------- Book and report readers

def book_steps(log):
    steps = []
    if log.exists():
        for line in log.read_text().splitlines():
            try:
                value = json.loads(line)
            except ValueError:
                continue
            if isinstance(value, dict) and isinstance(value.get('step'), dict):
                steps.append(value['step'])
    return steps


def report_lines(stdout):
    rows = []
    for line in stdout.splitlines():
        try:
            rows.append(json.loads(line))
        except ValueError:
            rows.append(dict(unparsed=line[:400]))
    return rows


def parsed(text):
    try:
        return json.loads(text) if isinstance(text, str) else text
    except ValueError:
        return text


def prefix_checks(bridge, model):
    """Each model and tool dispatch arrived when the Book on disk held exactly the steps before it."""
    rows = [(r['arrived'], r['transcript'] + 1, r['observed']) for r in model.requests if 'transcript' in r]
    rows += [(r['arrived'], int(r['call_id']), r['observed']) for r in bridge.dispatches]
    rows.sort()
    exact = all(obs == [n - 1, n - 1] or (n == 1 and obs in (None, [0, 0])) for _, n, obs in rows)
    return dict(book_prefix=exact, dispatch_order=[n for _, n, _ in rows] == sorted(n for _, n, _ in rows)), \
        [dict(step=n, observed=obs) for _, n, obs in rows]


def observations(bridge, steps):
    """Per remote tool call, the four observations from the journal and the Book separately."""
    journal = service.journal(bridge) or {'calls': {}}
    dispatched = {d['call_id']: d for d in bridge.dispatches}
    rows = []
    for step in steps:
        if step.get('kind') != 'tool':
            continue
        n = str(step.get('n'))
        received = parsed(step.get('result'))
        entry = journal['calls'].get(n)
        sent = dispatched.get(n)
        produced = entry.get('result') if entry else None
        core = service.core(bridge, entry['core_call_id']) if entry else None
        row = dict(step=int(n), tool=step.get('name'),
                   admission=dict(service='admitted' if entry else ('refused' if sent else 'not_dispatched'),
                                  book=received.get('accepted') if isinstance(received, dict) else None),
                   execution=dict(service=produced.get('execution') if produced else ('unknown' if entry else None),
                                  book=received.get('execution') if isinstance(received, dict) else None),
                   reply=dict(produced=produced is not None or (sent or {}).get('produced') is not None,
                              status=(sent or {}).get('status'),
                              received_equals_produced=produced is not None and received == produced),
                   service_ms=(sent or {}).get('service_ms'), book_took_ms=step.get('took_ms'), timeout_ms=(sent or {}).get('timeout_ms'),
                   state=received.get('state') if isinstance(received, dict) else None,
                   error=received.get('error') if isinstance(received, dict) else None)
        if step.get('name') == 'command' or (sent or {}).get('operation') == 'command':
            if core and 'observation' in core:
                clean = core['observation'].get('cleanup', {})
                row['cleanup'] = dict(execution_valid=core.get('execution_valid'),
                                      container_absent=clean.get('absent'), cgroup_absent=clean.get('cgroup_absent'),
                                      host_confirmed=clean.get('host_confirmed'))
                row['candidate_elapsed_s'] = core.get('elapsed_seconds')
                row['exit_code'] = core.get('exit_code')
            else:
                row['cleanup'] = 'no core result journalled' if entry else 'not dispatched'
        else:
            row['cleanup'] = 'no container (file operation)'
        rows.append(row)
    return rows


# ---------------------------------------------------------------- one run

class Run:
    def __init__(self, attempt, name, runtime, prefix, source, verifier, replies, goal,
                 on_dispatch=None, seconds=600, operator=None):
        self.__dict__.update(locals())
        self.dir = attempt.work / name
        self.root = self.dir / 'root'
        self.log = self.root / 'runs/r_1.log'
        (self.root / 'work').mkdir(parents=True)
        self.operator = operator or {'answer.txt': 'OPERATOR CANARY ' + secrets.token_hex(8) + '\n'}
        for path, text in self.operator.items():
            (self.root / 'work' / path).write_text(text)
        self.placeholders = tree_hash(self.root / 'work')

    def go(self):
        started = time.monotonic()
        self.bridge = service.start(self.dir / 'service', self.source, self.verifier, lambda: steps_in(self.log))
        self.model = Model(self.replies, observe=lambda: steps_in(self.log))
        config = service.write_config(self.bridge, self.dir / 'private/bridge.json')
        self.argv = self.prefix + ['application-workspace', str(self.root), '--model', f'127.0.0.1:{self.model.port}',
                                   '--config', str(config)] + self.goal.split()
        box = {}
        agent = threading.Thread(target=lambda: box.update(row=invoke(self.argv, self.seconds, cwd=self.dir)))
        agent_started = time.monotonic()
        agent.start()
        self.side = self.on_dispatch(self) if self.on_dispatch else None
        agent.join()
        self.agent_s = round(time.monotonic() - agent_started, 3)
        self.row = box['row']
        self.model.close()
        self.after = self.dispose()
        self.wall_s = round(time.monotonic() - started, 3)
        return self

    def dispose(self):
        """Freeze, protected verdict, close; or, with the owner gone, cleanup-only recovery."""
        b, out = self.bridge, {}
        owner_alive = b.process.poll() is None
        if owner_alive:
            t = time.monotonic()
            try:
                frozen = b.freeze()
                out['freeze'] = dict(ok=True, items=len(frozen.get('inventory', {}).get('items', [])), s=round(time.monotonic() - t, 3))
            except Exception as exc:
                out['freeze'] = dict(ok=False, error=f'{type(exc).__name__}: {exc}')
            if out['freeze']['ok']:
                t = time.monotonic()
                try:
                    out['verdict'] = verdict(b.verify(), self.verifier)
                except Exception as exc:
                    out['verdict'] = dict(passed=None, error=f'{type(exc).__name__}: {exc}')
                out['verdict']['s'] = round(time.monotonic() - t, 3)
            t = time.monotonic()
            out['closed'] = b.close(seconds=120)
            out['close_s'] = round(time.monotonic() - t, 3)
            if not out['closed']:
                b.stop_owner()
        journal = service.journal(b) or {}
        out['owner_cleanup'] = journal.get('cleanup')
        if (journal.get('cleanup') or {}).get('cleanup') != 'confirmed' and (b.directory / 'workspace/ownership.json').exists():
            t = time.monotonic()
            try:
                out['recovery'] = b.recover()
            except Exception as exc:
                out['recovery'] = dict(error=f'{type(exc).__name__}: {exc}')
            out['recovery_s'] = round(time.monotonic() - t, 3)
        receipt = b.directory / 'workspace/ownership.json'
        if receipt.exists():
            proof = workspace_absence([json.loads(receipt.read_bytes())])
            try:
                require_absent(proof)
                out['machine_absent'] = True
            except AssertionError:
                out['machine_absent'] = False
                out['absence'] = proof
        else:
            out['machine_absent'] = None
        return out

    # -- shared checks

    def token_absent(self):
        token = self.bridge.token
        texts = [self.row['stdout'], self.row['stderr'], ' '.join(self.argv)]
        texts += [r['raw'].decode('latin-1') for r in self.model.requests if 'raw' in r]
        private = {(self.dir / 'private/bridge.json').resolve(), (self.bridge.directory / 'capability.json').resolve()}
        scanned = 0
        for path in self.dir.rglob('*'):
            if path.is_file() and path.resolve() not in private:
                data = path.read_bytes()
                if path.suffix == '.gz':
                    data = gzip.decompress(data)
                texts.append(data.decode('latin-1'))
                scanned += 1
        self.scanned = scanned
        return all(token not in t for t in texts)

    def result(self, expected_exit, extra):
        steps = book_steps(self.log)
        lines = report_lines(self.row['stdout'])
        events = {}
        for l in lines:
            events.setdefault(l.get('event'), []).append(l)
        terminal = (events.get('terminal') or [{}])[-1].get('payload', {})
        per_call = observations(self.bridge, steps)
        prefix, arrivals = prefix_checks(self.bridge, self.model)
        results_text = json.dumps([s.get('result') for s in steps])
        checks = dict(exit_code=self.row['exit_code'] == expected_exit,
                      schema=bool(lines) and all(l.get('schema') == SCHEMA for l in lines),
                      token_absent=self.token_absent(),
                      operator_canary_absent=all(v.strip() not in results_text for v in self.operator.values()),
                      placeholders_unchanged=tree_hash(self.root / 'work') == self.placeholders,
                      machine_absent=self.after.get('machine_absent') is True,
                      **prefix)
        checks.update(extra(self, dict(steps=steps, events=events, terminal=terminal, calls=per_call)))
        model_times = [round(b['arrived'] - a['arrived'], 3) for a, b in zip(self.model.requests, self.model.requests[1:])]
        row = dict(part=self.attempt.part, case=self.name, runtime=self.runtime, passed=all(checks.values()),
                   exit_code=self.row['exit_code'], outcome=self.row['outcome'], guard_killed=self.row.get('guard_killed'),
                   elapsed_s=self.row['elapsed_s'], agent_s=self.agent_s, wall_s=self.wall_s,
                   startup_ms=self.bridge.startup_ms,
                   summary=json.dumps((events.get('terminal') or events.get('reporting_error') or [{}])[-1])[:400],
                   terminal=terminal, checks=checks, calls=per_call, arrivals=arrivals,
                   model_requests=len(self.model.requests), model_gaps_s=model_times,
                   book_steps=len(steps), after=self.after, files_scanned_for_token=getattr(self, 'scanned', None),
                   side=self.side)
        if not row['passed']:
            row['stdout'] = self.row['stdout'][-6000:]
            row['stderr'] = self.row['stderr'][-4000:]
        self.keep(steps)
        return row

    def keep(self, steps):
        """Small per-case evidence: the Book log, the service journal, and the report."""
        target = self.attempt.evidence / self.name
        target.mkdir(parents=True)
        if self.log.exists() and self.log.stat().st_size <= 262144:
            shutil.copyfile(self.log, target / 'book-r_1.log')
        journal = self.bridge.directory / 'owner.json'
        if journal.exists():
            shutil.copyfile(journal, target / 'service-journal.json')
        receipt = self.bridge.directory / 'workspace/ownership.json'
        if receipt.exists():
            shutil.copyfile(receipt, target / 'ownership.json')
        (target / 'report.jsonl').write_text(self.row['stdout'][-65536:])


def tree_hash(path):
    return {str(p.relative_to(path)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(path.rglob('*')) if p.is_file()} if path.exists() else None


def verdict(result, verifier):
    obs = result.get('observation', {})
    stdout = base64.b64decode(obs.get('stdout', '')).decode(errors='replace')
    stderr = base64.b64decode(obs.get('stderr', '')).decode(errors='replace')
    expected = verifier['checks'][0]['expected']
    first = next((i for i, (a, b) in enumerate(zip(stdout.splitlines(), expected.splitlines())) if a != b), None)
    return dict(passed=result.get('passed'), state=result.get('state'), execution=result.get('execution'),
                exit_code=result.get('exit_code'), execution_valid=result.get('execution_valid'),
                checks=[{k: c[k] for k in ('id', 'passed')} for c in result.get('checks', [])],
                readonly=result.get('manifest', {}).get('workspace', {}).get('readonly'),
                snapshot=bool(result.get('manifest', {}).get('workspace', {}).get('snapshot')),
                elapsed_seconds=result.get('elapsed_seconds'), stdout_equals_expected=stdout == expected,
                first_difference=None if first is None else dict(line=first + 1, got=stdout.splitlines()[first][:300],
                                                                  want=expected.splitlines()[first][:300]),
                tests_hash_equal=stdout.splitlines()[-1:] == expected.splitlines()[-1:],
                stdout_lines=len(stdout.splitlines()), expected_lines=len(expected.splitlines()),
                stdout=stdout[:6000], stderr_tail=stderr[-1500:])


# ---------------------------------------------------------------- attempts and parts

class Session:
    def __init__(self, part, runtime, name):
        self.part, self.runtime, self.name = part, runtime, name
        self.attempt = Attempt(name)
        self.work = WORK / name
        self.work.mkdir(parents=True, exist_ok=False)
        self.evidence = EVIDENCE / name
        self.evidence.mkdir()
        self.prefix = agent_prefix(runtime, self.work, self.attempt) if runtime != 'none' else None

    def record(self, row):
        return self.attempt.record(row)


def logstat_material(session):
    """Prepared trees, goldens, receipt, and the tests output of the clean tree on this host."""
    trees, goldens, receipt = prepare.trees()
    (session.evidence / 'fixture-receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    build = session.work / 'host-tests'
    prepare.write(trees['normalized'], build / 'src')
    row = invoke([MO, 'build', str(build / 'src/logstat/main.mo'), '--tests', '-o', 'logstat-tests'], 600, cwd=build)
    tests = invoke([str(build / 'zig-out/mo-build/logstat-tests/logstat-tests')], 60, cwd=build)
    if row['exit_code'] != 0 or tests['exit_code'] != 0:
        raise SystemExit('host tests of the normalized tree did not pass')
    return trees, goldens, receipt, tests['stdout']


def part_readiness(s, only):
    """Protected verifier alone, no agent: clean, faulty and repaired trees."""
    trees, goldens, receipt, tests_output = logstat_material(s)
    expect = {'clean': True, 'faulty': False, 'repaired': True}
    for name in only or list(expect):
        tree = trees[name]
        v = logstat_case.verifier(goldens, tree, tests_output)
        started = time.monotonic()
        b = service.start(s.work / name / 'service', tree, v, lambda: None)
        t = time.monotonic()
        frozen = b.freeze()
        freeze_s = round(time.monotonic() - t, 3)
        t = time.monotonic()
        result = verdict(b.verify(), v)
        verify_s = round(time.monotonic() - t, 3)
        closed = b.close(seconds=120)
        journal = service.journal(b)
        proof = workspace_absence([json.loads((b.directory / 'workspace/ownership.json').read_bytes())])
        try:
            require_absent(proof)
            absent = True
        except AssertionError:
            absent = False
        checks = dict(verdict=result['passed'] is expect[name], closed=closed,
                      cleanup=(journal or {}).get('cleanup', {}).get('cleanup') == 'confirmed', machine_absent=absent,
                      builds=result['stdout'].startswith('build=0\nbuild-tests=0\n'))
        if name == 'faulty':
            checks['semantic_red'] = (result['first_difference'] or {}).get('line', 0) > 3 and 'exit=1' in result['stdout'].split('== tests')[1][:20]
        s.record(dict(part='readiness', case=name, runtime='none', passed=all(checks.values()), checks=checks,
                      startup_ms=b.startup_ms, freeze_s=freeze_s, verify_s=verify_s,
                      wall_s=round(time.monotonic() - started, 3), freeze_items=len(frozen.get('inventory', {}).get('items', [])),
                      verdict=result, host_tests_output_matches=tests_output in result['stdout']))
        d = s.evidence / name
        d.mkdir()
        shutil.copyfile(b.directory / 'owner.json', d / 'service-journal.json')
        shutil.copyfile(b.directory / 'workspace/ownership.json', d / 'ownership.json')


# -- smoke

def smoke_source(canary):
    return {'answer.txt': b'before\n', 'canary.txt': canary.encode()}


SMOKE_VERIFIER = {'script': 'cat /workspace/answer.txt', 'seconds': 30,
                  'checks': [{'id': 'answer', 'stream': 'stdout', 'mode': 'exact', 'expected': 'after\n'}]}


def part_smoke(s, only):
    canary = 'CANDIDATE CANARY ' + secrets.token_hex(8) + '\n'
    replies = [tool('list_files', path='.'), tool('read_file', path='canary.txt'), tool('search', query='before'),
               tool('write_file', path='answer.txt', text='middle\n'),
               tool('exact_edit', path='answer.txt', old_text='middle', new_text='after'),
               tool('command', command='cat /workspace/answer.txt /workspace/canary.txt; '
                                       'test ! -e /Users && test ! -e /private && echo ISOLATED'),
               done('all six tools answered')]

    def extra(run, seen):
        calls, journal = seen['calls'], service.journal(run.bridge)
        results = [parsed(st.get('result')) for st in seen['steps'] if st.get('kind') == 'tool']
        command = results[5] if len(results) > 5 and isinstance(results[5], dict) else {}
        stdout = (command.get('result') or {}).get('stdout') or ''
        return dict(
            six_tools=[c['tool'] for c in calls] == ['list_files', 'read_file', 'search', 'write_file', 'exact_edit', 'command'],
            journal_matches_book=len(calls) == 6 and all(c['reply']['received_equals_produced'] for c in calls),
            all_admitted_completed=all(c['admission'] == dict(service='admitted', book=True) and
                                       c['execution'] == dict(service='completed', book='completed') for c in calls),
            candidate_canary_read=canary.strip() in json.dumps(results),
            command_saw_edit=stdout.startswith('after\n' + canary) and stdout.endswith('ISOLATED\n'),
            command_cleanup=isinstance(calls[5]['cleanup'], dict) and all(calls[5]['cleanup'].values()) if len(calls) > 5 else False,
            terminal=(seen['terminal'].get('state'), seen['terminal'].get('result')) == ('done', 'all six tools answered'),
            verdict=(run.after.get('verdict') or {}).get('passed') is True,
            journal_calls=len((journal or {}).get('calls', {})) == 6)

    run = Run(s, 'smoke', s.runtime, s.prefix, smoke_source(canary), SMOKE_VERIFIER, replies,
              'use each of the six tools once and answer').go()
    s.record(run.result(0, extra))


# -- the scripted Logstat repair and its two verdict controls

def logstat_replies(kind):
    fix = dict(path='logstat/main.mo', old_text='top: 1, since: None', new_text='top: 5, since: None')
    if kind == 'repair':
        middle = [tool('read_file', path='logstat/main.mo'), tool('exact_edit', **fix)]
    elif kind == 'wrong-candidate':
        # Leaves the fault and rewrites Main's first test to agree with it: the candidate's own
        # tests then pass, but the defaults (CLI golden) and the protected test bytes do not.
        middle = [tool('read_file', path='logstat/main.mo'),
                  tool('exact_edit', path='logstat/main.mo', old_text='  assert parsed.top == 5\n',
                       new_text='  assert parsed.top == 1\n')]
    else:  # forged-success: no repair; a written verdict file and a command that prints success
        middle = [tool('write_file', path='logstat/verdict.json', text='{"passed": true, "tests": 8}\n'),
                  tool('command', command='echo "8 passed, 0 failed, 0 skipped"; exit 0')]
        return [tool('command', command=logstat_case.CANDIDATE_COMMAND)] + middle + [done('repaired: 8 passed')]
    return ([tool('command', command=logstat_case.CANDIDATE_COMMAND)] + middle +
            [tool('command', command=logstat_case.CANDIDATE_COMMAND), done('repaired')])


def part_logstat(s, only):
    trees, goldens, receipt, tests_output = logstat_material(s)
    for kind in only or ['repair', 'forged-success', 'wrong-candidate']:
        v = logstat_case.verifier(goldens, trees['repaired'], tests_output)

        def extra(run, seen, kind=kind):
            calls = seen['calls']
            codes = [c.get('exit_code') for c in calls if c['tool'] == 'command']
            base = dict(
                steps=len(seen['steps']) == (7 if kind == 'forged-success' else 9),
                journal_matches_book=bool(calls) and all(c['reply']['received_equals_produced'] for c in calls),
                commands_clean=all(isinstance(c['cleanup'], dict) and all(c['cleanup'].values())
                                   for c in calls if c['tool'] == 'command'),
                red_first=codes[:1] == [1] and calls[0]['state'] == 'failure' and calls[0]['execution'] == dict(service='completed', book='completed'),
                terminal_done=seen['terminal'].get('state') == 'done')
            v = run.after.get('verdict') or {}
            if kind == 'repair':
                base.update(green_last=codes[-1:] == [0], edit_ok=calls[2]['state'] == 'success', verdict=v.get('passed') is True)
            else:
                base.update(candidate_claims_green=codes[-1:] == [0], verdict_refused=v.get('passed') is False,
                            verifier_ran=v.get('execution') == 'completed', verifier_built=v.get('stdout', '').startswith('build=0\nbuild-tests=0\n'))
                if kind == 'wrong-candidate':
                    base['test_bytes_refused'] = v.get('tests_hash_equal') is False
            return base

        run = Run(s, kind, s.runtime, s.prefix, trees['faulty'], v, logstat_replies(kind),
                  'logstat prints one row where it should print five by default; find and fix it', seconds=1200).go()
        s.record(run.result(0, extra))


# -- negative runs

def kill_owner_mid_command(run):
    """Once the command is dispatched and its container is running, kill the owner process."""
    end = time.monotonic() + 120
    while time.monotonic() < end and not any(d['operation'] == 'command' for d in run.bridge.dispatches):
        time.sleep(.05)
    time.sleep(8)
    t = time.monotonic()
    pid = run.bridge.process.pid
    run.bridge.process.kill()
    run.bridge.process.wait(timeout=5)
    return dict(owner_pid=pid, killed_after_dispatch_s=8, kill_s=round(time.monotonic() - t, 3))


def part_negatives(s, only):
    source = {'answer.txt': b'before\n'}
    trivial = {'script': 'cat /workspace/answer.txt', 'seconds': 30,
               'checks': [{'id': 'answer', 'stream': 'stdout', 'mode': 'exact', 'expected': 'before\n'}]}
    cases = only or ['service-killed', 'candidate-limit', 'outer-deadline']
    for name in cases:
        if name == 'service-killed':
            replies = [tool('command', command='echo RUNNING; sleep 40; echo DONE'), done('should not be asked')]

            def extra(run, seen):
                c = seen['calls'][0] if seen['calls'] else {}
                rec = run.after.get('recovery') or {}
                return dict(one_call=len(seen['calls']) == 1, execution_unknown=c.get('execution', {}).get('book') == 'unknown',
                            not_asked_again=len(run.model.requests) == 1,
                            terminal_stopped=seen['terminal'].get('state') == 'failed',
                            recovery_confirmed=rec.get('cleanup') == 'confirmed' and rec.get('execution') == 'unknown')
            run = Run(s, name, s.runtime, s.prefix, source, trivial, replies, 'wait for a slow command',
                      on_dispatch=kill_owner_mid_command).go()
            s.record(run.result(3, extra))
        elif name == 'candidate-limit':
            replies = [tool('command', command='echo START; sleep 200; echo END'), done('the command timed out')]

            def extra(run, seen):
                c = seen['calls'][0] if seen['calls'] else {}
                return dict(timeout_completed=(c.get('state'), c.get('execution', {}).get('book')) == ('timeout', 'completed'),
                            candidate_cap=c.get('timeout_ms') == 120000,
                            continued=len(run.model.requests) == 2,
                            terminal_done=seen['terminal'].get('state') == 'done',
                            command_cleanup=isinstance(c.get('cleanup'), dict) and all(c['cleanup'].values()),
                            verdict=(run.after.get('verdict') or {}).get('passed') is True)
            run = Run(s, name, s.runtime, s.prefix, source, trivial, replies, 'run a command past its limit').go()
            s.record(run.result(0, extra))
        elif name == 'outer-deadline':
            replies = [tool('command', command='echo START; sleep 200')] * 15 + [done('should not be reached')]

            def extra(run, seen):
                return dict(ended_before_guard=run.row['outcome'] == 'exited' and not run.row.get('guard_killed'),
                            within_outer=run.agent_s < 905,
                            no_done=seen['terminal'].get('state') != 'done',
                            last_call_truthful=all(c['execution']['book'] in ('completed', 'unknown', 'not_started', None)
                                                   for c in seen['calls']))
            run = Run(s, name, s.runtime, s.prefix, source, trivial, replies, 'keep running commands until the deadline',
                      seconds=1000).go()
            s.record(run.result(3, extra))


PARTS = {'readiness': part_readiness, 'smoke': part_smoke, 'logstat': part_logstat, 'negatives': part_negatives}


def main():
    part, runtime, name = sys.argv[1:4]
    only = sys.argv[sys.argv.index('--only') + 1].split(',') if '--only' in sys.argv else None
    if part not in PARTS or runtime not in ('interpreter', 'native', 'none') or (runtime == 'none') != (part == 'readiness'):
        raise SystemExit(__doc__)
    s = Session(part, runtime, name)
    try:
        PARTS[part](s, only)
    finally:
        print(json.dumps(dict(attempt=name, rows=str(s.attempt.path), failed=s.attempt.failed)), flush=True)
    sys.exit(int(s.attempt.failed))


if __name__ == '__main__':
    main()
