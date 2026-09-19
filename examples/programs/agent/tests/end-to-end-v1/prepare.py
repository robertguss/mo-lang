"""Logstat fixture preparation for the scripted repair: clean, normalized, faulty and repaired trees.

Everything is taken from this checkout's examples/programs (HEAD bytes, never the working tree),
kept outside examples/ in a caller-supplied directory, and described by a receipt of paths and
SHA-256s. Main's generated verified/proven footer is removed from the prepared baseline (fixture
preparation, not a repair); then only `top: 5` becomes `top: 1`. Goldens never enter a candidate."""
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[5]
MODULES = ['logstat/main.mo', 'logstat/parse.mo', 'logstat/report.mo', 'logstat/stats.mo']
INPUTS = ['logstat/fixture/a.log', 'logstat/fixture/b.log', 'logstat/fixture/c.log', 'logstat/fixture/notes.txt']
GOLDENS = ['logstat.expected', 'logstat-2.expected', 'logstat-3.expected', 'logstat-4.expected']
FAULT = ('  var parsed = Options(dir: "", top: 5, since: None, json: false)\n',
         '  var parsed = Options(dir: "", top: 1, since: None, json: false)\n')
FAULT_LINE = 80


def head(path):
    return subprocess.check_output(['git', '-C', str(ROOT), 'show', 'HEAD:examples/programs/' + path])


def sha(data):
    return hashlib.sha256(data).hexdigest()


def without_footer(main):
    """Main less its generated two-line footer (and the blank line before it)."""
    lines = main.decode().split('\n')
    at = next(i for i, line in enumerate(lines) if line.startswith('verified: '))
    if not lines[at + 1].lstrip().startswith('proven: ') or any(l.strip() for l in lines[at + 2:]):
        raise ValueError('unexpected footer shape')
    while at > 0 and not lines[at - 1].strip():
        at -= 1
    return ('\n'.join(lines[:at]) + '\n').encode()


def with_fault(main, fault):
    lines = main.decode().splitlines(keepends=True)
    old, new = fault
    if lines[FAULT_LINE - 1] != old or main.decode().count(old) != 1:
        raise ValueError('fault line moved')
    lines[FAULT_LINE - 1] = new
    return ''.join(lines).encode()


def trees():
    """name -> {path: bytes} for the four candidate trees, plus goldens and a receipt."""
    ids = json.loads(head('.mo.ids'))
    selected = [row for row in ids['files'] if row['path'] in MODULES]
    if sorted(r['path'] for r in selected) != sorted(MODULES):
        raise ValueError('missing ID record')
    base = {'mo.root': head('mo.root'), '.mo.ids': json.dumps({**ids, 'files': selected}, indent=2).encode() + b'\n'}
    base.update({p: head(p) for p in MODULES + INPUTS})
    clean_main = base['logstat/main.mo']
    normalized = without_footer(clean_main)
    faulty = with_fault(normalized, FAULT)
    repaired = with_fault(faulty, FAULT[::-1])
    out = {'clean': dict(base), 'normalized': dict(base, **{'logstat/main.mo': normalized}),
           'faulty': dict(base, **{'logstat/main.mo': faulty}), 'repaired': dict(base, **{'logstat/main.mo': repaired})}
    if any(len(v) > 65536 for tree in out.values() for v in tree.values()):
        raise ValueError('file over the workspace import bound')
    goldens = {g: head('logstat/' + g) for g in GOLDENS}
    receipt = {'head': subprocess.check_output(['git', '-C', str(ROOT), 'rev-parse', 'HEAD']).decode().strip(),
               'ids_sha256': sha(head('.mo.ids')), 'id_scope': MODULES,
               'fault': {'line': FAULT_LINE, 'old': FAULT[0], 'new': FAULT[1]},
               'trees': {name: {p: sha(d) for p, d in sorted(t.items())} for name, t in out.items()},
               'goldens': {g: sha(d) for g, d in goldens.items()},
               'repaired_equals_normalized': repaired == normalized}
    return out, goldens, receipt


def write(tree, directory):
    directory = Path(directory)
    for path, data in tree.items():
        target = directory / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
    return directory


if __name__ == '__main__':
    import sys
    out, goldens, receipt = trees()
    target = Path(sys.argv[1])
    target.mkdir(parents=True, exist_ok=False)
    for name, tree in out.items():
        write(tree, target / name)
    print(json.dumps(receipt, indent=2))
