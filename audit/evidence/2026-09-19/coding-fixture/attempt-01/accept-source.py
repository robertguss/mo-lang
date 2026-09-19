"""Bounded lead verification of the integrated coding fixture commit."""
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import subprocess

ROOT = Path(__file__).resolve().parents[4]
OUT = Path(__file__).resolve().parent / 'attempt-01'
OUT.mkdir(exist_ok=False)
WORKER = '84d442e2fa019d8f69e8ca0e0b746b9a7a5a892f'
BASE = '5f87021a754474b8d742f39b0965b3e10d777573'
PRE = '54c3dcd8617c8d693fddee8efda99e03ac05e879'
HEAD = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
HERE = ROOT / 'examples/programs/agent/tests/coding-fixture-v1'
GUARD = ROOT / 'toolchain/bench/step36/guard.py'


def blob(rev, path):
    return subprocess.check_output(['git', 'show', rev + ':' + path], cwd=ROOT)


def blocks(raw):
    text = raw.decode()
    starts = list(re.finditer(r'^    \{\n      "path": "([^"]+)"', text, re.M))
    return {m.group(1): text[m.start():starts[i + 1].start() if i + 1 < len(starts) else text.rfind('\n  ]')].rstrip(',\n ') for i, m in enumerate(starts)}


paths = subprocess.check_output(['git', 'diff', '--name-only', BASE, WORKER], cwd=ROOT, text=True).splitlines()
for p in paths:
    if p != 'examples/programs/.mo.ids':
        assert (ROOT / p).read_bytes() == blob(WORKER, p), p
ids = 'examples/programs/.mo.ids'
old, worker, pre, merged = [blocks(blob(rev, ids)) for rev in [BASE, WORKER, PRE, HEAD]]
changed = {p for p in old.keys() | worker.keys() if old.get(p) != worker.get(p)}
assert len(changed) == 19
expected = {**pre, **{p: worker[p] for p in changed}}
assert merged == expected
tracked = subprocess.check_output(['git', 'ls-files', 'examples', 'toolchain'], cwd=ROOT, text=True).splitlines()
before = {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in tracked if (ROOT / p).is_file()}
(OUT / 'source-identity.json').write_text(json.dumps({'worker': WORKER, 'integrated': HEAD, 'changed_files': len(paths), 'exact_worker_files': len(paths) - 1, 'worker_id_records': sorted(changed), 'preserved_main_records': len(pre) - len(changed & pre.keys()), 'passed': True}, indent=2) + '\n')


def run(name, seconds, args):
    command = ['python3', str(GUARD), str(seconds), '--', *map(str, args)]
    started = datetime.now().astimezone().isoformat()
    with (OUT / (name + '.stdout.txt')).open('w') as out, (OUT / (name + '.stderr.txt')).open('w') as err:
        p = subprocess.Popen(command, cwd=ROOT, stdout=out, stderr=err, start_new_session=True)
        try:
            rc = p.wait(timeout=seconds + 5)
        finally:
            rows = subprocess.check_output(['ps', '-axo', 'pid=,pgid=,command='], text=True).splitlines()
            left = [r for r in rows if len(r.split(None, 2)) == 3 and r.split(None, 2)[1] == str(p.pid)]
            if left:
                os.killpg(p.pid, signal.SIGKILL)
                p.wait(timeout=5)
    record = {'command': command, 'exit_code': rc, 'started': started, 'finished': datetime.now().astimezone().isoformat(), 'remaining_group': left}
    (OUT / (name + '.status.json')).write_text(json.dumps(record, indent=2) + '\n')
    print(json.dumps({'check': name, **record}), flush=True)
    if rc or left:
        raise RuntimeError(name + ' failed; evidence retained')


try:
    for name, args in [('verify', ['python3', HERE / 'verify.py']), ('cancel', ['python3', HERE / 'cancel-checks.py']),
                       ('interpreter', ['python3', HERE / 'run.py', 'interpreter']), ('compiled', ['python3', HERE / 'run.py', 'compiled']),
                       ('extra', ['python3', Path(__file__).with_name('lead-controls.py')]), ('full', ['python3', HERE / 'full.py'])]:
        run(name, 600, args)
finally:
    after = {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in before}
    changed_bytes = [p for p in before if before[p] != after[p]]
    (OUT / 'source-after.json').write_text(json.dumps({'files': len(before), 'tracked_bytes_unchanged': not changed_bytes, 'changed': changed_bytes}, indent=2) + '\n')
    assert not changed_bytes, changed_bytes
