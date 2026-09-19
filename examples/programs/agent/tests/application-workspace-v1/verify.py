"""Focused local verification of the slice and what it must preserve, one part per attempt.
Usage: verify.py mo|inherited ATTEMPT

mo: formatter check of every agent source; mo test on every agent source with the simulation
its verified line records (100 seeds at the default 5% faults), so every verified line and
record is current; the model client's recipe conformance; native test builds of the owned and
dependent modules, each run.
inherited: the current native agent built before any legacy case; the 12 legacy CLI goldens;
the coding-fixture 22-case matrix in each runtime and its cancellation report control; the
terminal-auth 9 cases in each runtime. Shared test sources are only run, never written."""
import json
import os
import sys

from common import AGENT, MO, ROOT, Attempt, invoke, trimmed

FIXTURE = AGENT / 'tests/coding-fixture-v1'
AUTH = AGENT / 'tests/terminal-auth'
NATIVE_TESTS = ['workspace-adapter', 'report', 'run', 'application', 'main', 'registry', 'coding-fixture',
                'check', 'server', 'runs', 'tests/application-workspace-v1/boundaries',
                'tests/coding-fixture-v1/boundaries']


def sources():
    return sorted(AGENT.rglob('*.mo'))


def executable(path):
    magic = path.read_bytes()[:4] if path.is_file() else b''
    return os.access(path, os.X_OK) and magic in (b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf', b'\x7fELF')


def run(attempt, label, command, seconds=600, ok=None, cases=False, **more):
    row = invoke(command, seconds)
    passed = row['exit_code'] == 0 if ok is None else ok(row)
    if cases:
        # An inherited suite prints one JSON line per case with its own passed flag.
        found = []
        for line in row['stdout'].splitlines():
            try:
                found.append(json.loads(line))
            except ValueError:
                pass
        rows = [r for r in found if isinstance(r, dict) and 'passed' in r]
        more['cases'] = [sum(1 for r in rows if r['passed'] is True), len(rows)]
        more['case_names'] = [r.get('case', r.get('fixture')) for r in rows if r['passed'] is not True]
    return attempt.record(trimmed(dict(row, check=label, **more), passed))


def part_mo(attempt):
    for path in sources():
        rel = str(path.relative_to(ROOT))
        run(attempt, 'fmt-check', [MO, 'fmt', '--check', str(path)], 60, file=rel)
    for path in sources():
        rel = str(path.relative_to(ROOT))
        sim = ['--sim', '100'] if 'sim (100 runs' in path.read_text() else []
        run(attempt, 'test', [MO, 'test', str(path)] + sim, 900, file=rel)
    run(attempt, 'model-recipe', [MO, 'check', '--recipe', 'Recipes.AgentModelClientV1.ModelClient',
                                  str(AGENT / 'model.mo')], 300)
    for name in NATIVE_TESTS:
        binary = 'application-test-' + name.replace('/', '-')
        built = run(attempt, 'build-tests', [MO, 'build', '--tests', str(AGENT / (name + '.mo')), '-o', binary], 900, file=name)
        if built['passed']:
            run(attempt, 'native-tests', [str(ROOT / 'zig-out/mo-build' / binary / binary)], 900, file=name)


def part_inherited(attempt):
    agent = ROOT / 'zig-out/mo-build/coding-fixture/coding-fixture'
    built = run(attempt, 'build-agent', [MO, 'build', str(AGENT / 'main.mo'), '-o', 'coding-fixture'], 900,
                ok=lambda row: row['exit_code'] == 0 and executable(agent))
    if not built['passed']:
        return
    run(attempt, 'legacy-goldens', [sys.executable, str(FIXTURE / 'legacy.py')], 300, cases=True)
    for mode in ['interpreter', 'compiled']:
        run(attempt, 'coding-fixture-' + mode, [sys.executable, str(FIXTURE / 'run.py'), mode], 1200, cases=True)
    if run(attempt, 'build-cancel', [MO, 'build', str(FIXTURE / 'boundaries.mo'), '-o', 'coding-fixture-cancel'], 900)['passed']:
        for mode in ['interpreter', 'compiled']:
            run(attempt, 'coding-fixture-cancel-' + mode, [sys.executable, str(FIXTURE / 'cancel.py'), mode], 300, cases=True)
    if run(attempt, 'build-terminal-auth', [MO, 'build', str(AUTH / 'driver.mo'), '-o', 'terminal-auth'], 900)['passed']:
        for mode in ['interpreter', 'compiled']:
            run(attempt, 'terminal-auth-' + mode, [sys.executable, str(AUTH / 'run.py'), mode], 600, cases=True)


def main():
    part, name = sys.argv[1], sys.argv[2]
    if part not in ('mo', 'inherited'):
        raise SystemExit('part is mo or inherited')
    attempt = Attempt(name)
    part_mo(attempt) if part == 'mo' else part_inherited(attempt)
    sys.exit(int(attempt.failed))


if __name__ == '__main__':
    main()
