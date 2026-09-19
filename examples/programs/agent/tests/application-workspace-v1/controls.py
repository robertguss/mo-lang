"""Carried-finding controls. Mo controls are kept as .mo.txt and materialized into a fresh
program root outside examples/, beside a copy of the current agent sources, so the corpus
never reads them. Usage: controls.py ATTEMPT [name ...]"""
import shutil
import sys
import tempfile
from pathlib import Path

from common import AGENT, HERE, MO, ROOT, Attempt, invoke, trimmed

MO_CONTROLS = {'findings': 'controls/findings.mo.txt', 'near': 'controls/near.mo.txt'}
PY_CONTROLS = {'guard': 'guard_control.py', 'evidence': 'evidence_control.py'}


def materialized(tmp, name):
    root = Path(tmp)
    (root / 'mo.root').write_text('')
    # The aggregate sidecar keeps the copied sources' verified lines checkable.
    shutil.copy2(AGENT.parent / '.mo.ids', root / '.mo.ids')
    shutil.copytree(AGENT, root / 'agent', ignore=shutil.ignore_patterns('tests', 'data', 'measure', '*.expected'))
    target = root / 'agent/tests/red' / (name + '.mo')
    target.parent.mkdir(parents=True)
    target.write_bytes((HERE / MO_CONTROLS[name]).read_bytes())
    return target


def mo_control(attempt, name):
    with tempfile.TemporaryDirectory(prefix='mo-app-red-') as tmp:
        target = materialized(tmp, name)
        row = invoke([MO, 'test', str(target)], 300)
        attempt.record(trimmed(dict(row, control=name, runtime='interpreter'), row['exit_code'] == 0))
        binary = 'app-red-' + name
        built = invoke([MO, 'build', '--tests', str(target), '-o', binary], 600)
        attempt.record(trimmed(dict(built, control=name, runtime='native-build'), built['exit_code'] == 0))
        if built['exit_code'] == 0:
            ran = invoke([str(ROOT / 'zig-out/mo-build' / binary / binary)], 300)
            attempt.record(trimmed(dict(ran, control=name, runtime='native'), ran['exit_code'] == 0))


def py_control(attempt, name):
    row = invoke([sys.executable, str(HERE / PY_CONTROLS[name])], 120)
    attempt.record(trimmed(dict(row, control=name, runtime='python'), row['exit_code'] == 0))


def main():
    attempt = Attempt(sys.argv[1])
    names = sys.argv[2:] or list(MO_CONTROLS) + list(PY_CONTROLS)
    unknown = [n for n in names if n not in MO_CONTROLS and n not in PY_CONTROLS]
    if unknown or len(set(names)) != len(names):
        raise SystemExit(f'unknown or repeated controls: {names}')
    for name in names:
        (mo_control if name in MO_CONTROLS else py_control)(attempt, name)
    sys.exit(int(attempt.failed))


if __name__ == '__main__':
    main()
