"""Independent lead checks on an exact integrated recovery worker tree."""
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent
MODE, NAME, WORKER = sys.argv[1:]
assert MODE in ('local', 'recovery', 'full') and re.fullmatch(r'[a-z0-9-]+', NAME)
assert re.fullmatch(r'[0-9a-f]{40}', WORKER)
OUT = HERE / NAME
OUT.mkdir(exist_ok=False)
EXECUTOR = ROOT / 'toolchain/harness/executor'
RECOVERY = EXECUTOR / 'recovery'
GUARD = ROOT / 'toolchain/bench/step36/guard.py'
BASE = '90858791f441d125f0187a6751beffec6ef2312b'


def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT, text=True)


assert not git('diff', '--name-only', WORKER, 'HEAD', '--', 'toolchain/harness/executor')
paths = git('ls-files', 'toolchain', 'examples').splitlines()
baseline = {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in paths}
(OUT / 'source-before.json').write_text(json.dumps({'head': git('rev-parse', 'HEAD').strip(),
    'worker': WORKER, 'exact_worker_files': len(git('diff', '--name-only', BASE, WORKER).splitlines()),
    'hashes': baseline}, indent=2))


def run(name, seconds, args, cwd=ROOT, expected=0):
    argv = ['python3', str(GUARD), str(seconds), '--', *map(str, args)]
    started = datetime.now().astimezone().isoformat()
    forced = False
    with (OUT / (name + '.stdout.txt')).open('xb') as out, (OUT / (name + '.stderr.txt')).open('xb') as err:
        p = subprocess.Popen(argv, cwd=cwd, stdout=out, stderr=err, start_new_session=True)
        try:
            rc = p.wait(timeout=seconds + 10)
        except subprocess.TimeoutExpired:
            forced, rc = True, 124
        finally:
            snapshot = subprocess.check_output(['ps', '-axo', 'pid=,pgid=,command='], text=True)
            remaining = [r for r in snapshot.splitlines() if len(r.split(None, 2)) == 3 and r.split(None, 2)[1] == str(p.pid)]
            try:
                os.killpg(p.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            p.wait(timeout=5)
            time.sleep(.1)
    try:
        os.killpg(p.pid, 0)
        left = True
    except ProcessLookupError:
        left = False
    record = {'argv': argv, 'cwd': str(cwd), 'started': started,
        'finished': datetime.now().astimezone().isoformat(), 'exit': rc, 'expected_exit': expected,
        'forced': forced, 'group': p.pid, 'cleanup_before': remaining, 'group_remaining': left}
    (OUT / (name + '.status.json')).write_text(json.dumps(record, indent=2))
    print(json.dumps({'check': name, 'exit': rc, 'group_remaining': left}), flush=True)
    assert rc == expected and not forced and not remaining and not left, name


def shared(name):
    p = subprocess.run(['docker', '--context', 'orbstack', 'ps', '-a', '--no-trunc',
                        '--format', '{{json .}}'], capture_output=True, text=True, timeout=15)
    (OUT / (name + '.json')).write_text(json.dumps({'exit': p.returncode, 'stdout': p.stdout, 'stderr': p.stderr}))
    p.check_returncode()
    return sorted((json.loads(row)['ID'], json.loads(row)['State']) for row in p.stdout.splitlines())


before = shared('shared-before') if MODE == 'recovery' else None
try:
    if MODE == 'full':
        run('build', 180, ['zig', 'build'], ROOT / 'toolchain')
        run('test', 900, ['zig', 'build', 'test', '--summary', 'all'], ROOT / 'toolchain')
    elif MODE == 'local':
        run('local', 120, ['python3', '-B', RECOVERY / 'local_suite.py'])
        run('schema-extra', 30, ['python3', '-B', HERE / 'schema-controls.py', OUT / 'schema-extra'])
        for name, selection in [('unknown', ['not-a-group']), ('empty', []),
                                ('duplicate', ['create-before', 'create-before'])]:
            output = OUT / ('reject-' + name)
            run('selection-' + name, 30, ['python3', '-B', RECOVERY / 'live.py', output, '--groups', *selection], expected=2)
            assert not output.exists(), name
    else:
        run('readiness', 90, ['python3', '-B', HERE / 'inventory.py', OUT, '--readiness'])
        run('recovery', 900, ['python3', '-B', RECOVERY / 'live.py', OUT / 'live'])
        selected = json.loads((OUT / 'live/selected.json').read_text())
        results = json.loads((OUT / 'live/results.json').read_text())
        assert len(selected['fixed']) == 16 and selected['selected'] == selected['fixed']
        assert [r['group'] for r in results] == selected['fixed'] and all(r['ok'] for r in results)
        cleanup = json.loads((OUT / 'live/cleanup.json').read_text())
        assert cleanup and all(r['cleanup'] == 'confirmed' and r['execution'] == 'unknown' for r in cleanup)
        run('regressions', 1500, ['python3', '-B', RECOVERY / 'regressions.py', OUT / 'regressions'])
        exits = json.loads((OUT / 'regressions/exits.json').read_text())
        assert [r['name'] for r in exits] == ['workspace22', 'executor17', 'lifecycle1', 'application23']
        assert all(r['exit'] == 0 for r in exits)
        run('extra', 180, ['python3', '-B', HERE / 'lead-controls.py', OUT / 'extra'])
        run('inventory', 90, ['python3', '-B', HERE / 'inventory.py', OUT])
finally:
    changed = [p for p, digest in baseline.items() if hashlib.sha256((ROOT / p).read_bytes()).hexdigest() != digest]
    (OUT / 'source-after.json').write_text(json.dumps({'files': len(baseline), 'changed': changed,
        'tracked_bytes_unchanged': not changed}, indent=2))
    if before is not None:
        after = shared('shared-after')
        (OUT / 'shared-comparison.json').write_text(json.dumps({'before': before, 'after': after,
            'unchanged': before == after}, indent=2))
        assert before == after and len(before) == 5
    assert not changed, changed
    size = sum(p.lstat().st_size for p in OUT.rglob('*') if p.is_file())
    (OUT / 'retained-bytes.json').write_text(json.dumps({'bytes_before_this_record': size, 'budget': 16 * 1024 * 1024}))
    assert size < 16 * 1024 * 1024
