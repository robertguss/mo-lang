"""Format owned sources and regenerate verified lines and aggregate records for them and their
discovered dependency closure, with actual mo commands. Usage: closure.py ATTEMPT

A manifest of every agent source and the aggregate record is taken before any write. Owned
modules are written first, in dependency order; then every agent module is checked, and each one
reporting a stale verified line (MO0317) is written again, keeping the simulation it had (a line
recording sim (100 runs ...) is rewritten with --sim 100, at the default 5% faults), until none is
stale. Non-owned sources must come out byte-identical; only their aggregate records may change."""
import hashlib
import json
import sys

from common import AGENT, MO, ROOT, Attempt, invoke, trimmed

IDS = AGENT.parent / '.mo.ids'
OWNED = ['workspace-adapter', 'report', 'run', 'application', 'main',
         'tests/application-workspace-v1/driver', 'tests/application-workspace-v1/boundaries']


def sources():
    return sorted(p for p in AGENT.rglob('*.mo'))


def manifest():
    rows = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources()}
    rows[str(IDS.relative_to(ROOT))] = hashlib.sha256(IDS.read_bytes()).hexdigest()
    return rows


def simulated(path):
    return 'sim (100 runs' in path.read_text()


def write(attempt, path):
    args = [MO, 'test', '--write', str(path)] + (['--sim', '100'] if simulated(path) or path.name == 'boundaries.mo' and 'application-workspace-v1' in str(path) else [])
    row = invoke(args, 900)
    attempt.record(trimmed(dict(row, check='write', file=str(path.relative_to(ROOT))), row['exit_code'] == 0))
    return row['exit_code'] == 0


def graph():
    module_of, uses = {}, {}
    for path in sources():
        lines = path.read_text().splitlines()
        name = next((l.split()[1] for l in lines if l.startswith('module ')), '')
        module_of[name] = path
        uses[path] = [module_of_use for module_of_use in
                      (l.split()[1].split('{')[0] for l in lines if l.startswith('use '))]
    return module_of, uses


def ordered(paths):
    """Dependencies before their users, from each file's module and use lines."""
    module_of, uses = graph()
    done, order = set(), []
    def visit(path):
        if path in done:
            return
        done.add(path)
        for module in uses.get(path, []):
            if module in module_of:
                visit(module_of[module])
        order.append(path)
    for path in sources():
        visit(path)
    wanted = {p.resolve() for p in paths}
    return [p for p in order if p.resolve() in wanted]


def dependents(paths):
    """The given files and every file whose uses reach one of them."""
    module_of, uses = graph()
    reached = {p.resolve() for p in paths}
    changed = True
    while changed:
        changed = False
        for path, used in uses.items():
            if path.resolve() not in reached and any(m in module_of and module_of[m].resolve() in reached for m in used):
                reached.add(path.resolve())
                changed = True
    return [p for p in sources() if p.resolve() in reached]


def stale():
    found = []
    for path in sources():
        row = invoke([MO, 'check', str(path)], 300)
        text = row['stdout'] + row['stderr']
        for line in text.splitlines():
            if ' MO0317 ' in line:
                found.append(line.split(':', 1)[0])
    return sorted({(ROOT / f).resolve() for f in found})


def main():
    attempt = Attempt(sys.argv[1])
    before = manifest()
    attempt.record(dict(check='manifest-before', manifest=before, passed=True))
    owned = [AGENT / (name + '.mo') for name in OWNED if (AGENT / (name + '.mo')).exists()]
    for path in owned:
        row = invoke([MO, 'fmt', str(path)], 60)
        attempt.record(trimmed(dict(row, check='fmt', file=str(path.relative_to(ROOT))), row['exit_code'] == 0))
    closure = dependents(owned)
    attempt.record(dict(check='closure', files=[str(p.relative_to(ROOT)) for p in ordered(closure)], passed=True))
    for path in ordered(closure):
        write(attempt, path)
    for round in range(6):
        pending = stale()
        attempt.record(dict(check='stale', round=round, passed=True,
                            files=[str(p.relative_to(ROOT)) for p in pending]))
        if not pending:
            break
        for path in ordered(pending):
            write(attempt, path)
    else:
        attempt.record(dict(check='closure-converged', passed=False))
    after = manifest()
    owned_names = {str(p.relative_to(ROOT)) for p in owned}
    changed = sorted(k for k in after if before.get(k) != after[k])
    foreign = [k for k in changed if k not in owned_names and not k.endswith('.mo.ids')]
    attempt.record(dict(check='manifest-after', changed=changed, foreign_source_changes=foreign,
                        manifest=after, passed=not foreign))
    sys.exit(int(attempt.failed))


if __name__ == '__main__':
    main()
