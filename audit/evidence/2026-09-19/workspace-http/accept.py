"""Independent lead checks on an exact integrated workspace HTTP worker tree."""
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
assert MODE in ('local', 'busybox', 'application', 'regression', 'extra', 'full') and re.fullmatch(r'[a-z0-9-]+', NAME)
assert re.fullmatch(r'[0-9a-f]{40}', WORKER)
OUT = HERE / NAME
OUT.mkdir(exist_ok=False)
EXECUTOR = ROOT / 'toolchain/harness/executor'
RECOVERY = EXECUTOR / 'recovery'
GUARD = ROOT / 'toolchain/bench/step36/guard.py'
BASE = '3023a01a744d1580ca9814e595ddf990a12e456d'
HTTP = EXECUTOR / 'workspace_http'


def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT, text=True)


assert not git('diff', '--name-only', WORKER, 'HEAD', '--', 'toolchain/harness/executor')
owned = git('diff', '--name-only', BASE, WORKER).splitlines()
assert owned and all(p.startswith('toolchain/harness/executor/workspace_http/') for p in owned)
assert not git('diff', '--name-only', BASE, WORKER, '--', 'toolchain/harness/executor',
               ':(exclude)toolchain/harness/executor/workspace_http')
(OUT / 'worker-scope-proof.json').write_text(json.dumps({'worker': WORKER, 'files': len(owned),
    'only_new_workspace_http': True, 'core_unchanged': True}, indent=2))
paths = git('ls-files', 'toolchain', 'examples').splitlines()
def fingerprint(path):
    path = ROOT / path
    data = b'link:' + os.fsencode(os.readlink(path)) if path.is_symlink() else b'file:' + path.read_bytes()
    return hashlib.sha256(data).hexdigest()


baseline = {p: fingerprint(p) for p in paths}
(OUT / 'source-before.json').write_text(json.dumps({'head': git('rev-parse', 'HEAD').strip(),
    'worker': WORKER, 'exact_worker_files': len(git('diff', '--name-only', BASE, WORKER).splitlines()),
    'hashing': 'SHA256 of file: plus file bytes, or link: plus link target bytes',
    'hashes': baseline}, indent=2))


def run(name, seconds, args, cwd=ROOT, expected=0):
    argv = ['python3', str(GUARD), str(seconds), '--', *map(str, args)]
    started = datetime.now().astimezone().isoformat()
    forced = False
    with (OUT / (name + '.stdout.txt')).open('xb') as out, (OUT / (name + '.stderr.txt')).open('xb') as err:
        p = subprocess.Popen(argv, cwd=cwd, stdout=out, stderr=err, start_new_session=True)
        (OUT / (name + '.started.json')).write_text(json.dumps({'group': p.pid, 'argv': argv, 'started': started}))
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


before = shared('shared-before') if MODE in ('busybox', 'application', 'regression', 'extra') else None
try:
    if MODE == 'full':
        run('build', 180, ['zig', 'build'], ROOT / 'toolchain')
        run('test', 900, ['zig', 'build', 'test', '--summary', 'all'], ROOT / 'toolchain')
    elif MODE == 'local':
        run('http-local', 180, ['python3', '-B', HTTP / 'local.py'])
        run('inherited-local', 120, ['python3', '-B', RECOVERY / 'local_suite.py'])
        for name, selection in [('unknown', 'not-a-group'), ('empty', ''),
                                ('duplicate', 'deadlines,deadlines')]:
            for runner in ('local.py', 'live.py'):
                output = OUT / ('reject-' + name + '-' + runner[:-3])
                args = ['python3', '-B', HTTP / runner]
                if runner == 'live.py':
                    args.append(output)
                run('selection-' + name + '-' + runner[:-3], 30,
                    [*args, '--groups', selection], expected=2)
                assert not output.exists()
    else:
        inventory = HERE.parent / 'workspace-recovery/inventory.py'
        run('readiness', 60, ['python3', '-B', inventory, OUT, '--readiness'])
        if MODE in ('busybox', 'application'):
            args = ['python3', '-B', HTTP / 'live.py', OUT / 'live']
            if MODE == 'application':
                args.append('--application')
            run('http-live', 900, args)
            selected = json.loads((OUT / 'live/selected.json').read_text())
            results = json.loads((OUT / 'live/results.json').read_text())
            assert len(selected['fixed']) == 22 and selected['groups'] == selected['fixed']
            assert [r['group'] for r in results] == selected['fixed'] and all(r['passed'] for r in results)
            assert selected['application'] == (MODE == 'application')
            run('review-live', 180, ['python3', '-B', HTTP / 'review_live.py', OUT / 'review-live'])
        elif MODE == 'extra':
            run('extra', 180, ['python3', '-B', HERE / 'lead-controls.py', OUT / 'extra'])
        else:
            for suite, seconds, count in [('workspace22', 240, 22), ('executor17', 180, 17),
                                          ('lifecycle1', 120, 1), ('application23', 420, 23)]:
                run(suite, seconds, ['python3', '-B', RECOVERY / 'observe_regression.py', suite, OUT / suite])
                controls = OUT / suite / 'controls'
                if suite == 'lifecycle1':
                    assert json.loads((controls / 'collector-kill.json').read_text())['exit_code'] == -9
                    proof = json.loads((controls / 'reaped.json').read_text())
                    assert proof['absent'] and proof['cgroup_absent']
                else:
                    summary = json.loads((controls / 'summary.json').read_text())
                    assert summary['passed'] == count and summary.get('controls', summary.get('count')) == count
                    if suite == 'application23':
                        selection = json.loads((controls / 'selected.json').read_text())
                        assert len(selection['fixed']) == count and selection['selected'] == selection['fixed']
        run('inventory', 60, ['python3', '-B', inventory, OUT])

finally:
    changed = [p for p, digest in baseline.items() if fingerprint(p) != digest]
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
