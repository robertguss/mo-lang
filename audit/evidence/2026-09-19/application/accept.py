"""Lead acceptance on integrated immutable sources; retains each new attempt."""
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent
OUT = HERE / sys.argv[2]
OUT.mkdir(exist_ok=False)
MODE = sys.argv[1]
assert MODE in ('application', 'full')
EXECUTOR = ROOT / 'toolchain/harness/executor'
APP = EXECUTOR / 'application'
GUARD = ROOT / 'toolchain/bench/step36/guard.py'
WORKER = '0b93d5df22b7a49fe135b231256271e8245feebb'
BASE = '5e5682274d0d02ac5532f07a075c11a8e52345e3'
ARCHIVE = '/private/tmp/mo-linux-toolchain-bcqwt2vz/zig-aarch64-linux-0.16.0.tar.xz'
MANIFEST = 'd31b5c5e7e1912f98eba21268854d0f7b830dba7048b2de0e2c0458d10e507eb'

def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT, text=True)

assert not git('diff', '--name-only', WORKER, 'HEAD', '--', 'toolchain/harness/executor')
paths = git('ls-files', 'toolchain', 'examples').splitlines()
baseline = {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in paths}
(OUT / 'source-before.json').write_text(json.dumps({'head': git('rev-parse', 'HEAD').strip(),
    'worker': WORKER, 'exact_worker_files': len(git('diff', '--name-only', BASE, WORKER).splitlines()),
    'hashes': baseline}, indent=2))

def run(name, seconds, args, cwd=ROOT):
    argv = ['python3', str(GUARD), str(seconds), '--', *map(str, args)]
    started = datetime.now().astimezone().isoformat()
    forced = False
    with (OUT / (name + '.stdout.txt')).open('wb') as out, (OUT / (name + '.stderr.txt')).open('wb') as err:
        p = subprocess.Popen(argv, cwd=cwd, stdout=out, stderr=err, start_new_session=True)
        try:
            rc = p.wait(timeout=seconds + 10)
        except subprocess.TimeoutExpired:
            forced = True
            rc = 124
        finally:
            before = subprocess.check_output(['ps', '-axo', 'pid=,pgid=,command='], text=True)
            remaining = [r for r in before.splitlines() if len(r.split(None, 2)) == 3 and r.split(None, 2)[1] == str(p.pid)]
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
        'finished': datetime.now().astimezone().isoformat(), 'exit': rc,
        'forced': forced, 'cleanup_before': remaining, 'group_remaining': left}
    (OUT / (name + '.status.json')).write_text(json.dumps(record, indent=2))
    print(json.dumps({'check': name, 'exit': rc, 'group_remaining': left}), flush=True)
    assert rc == 0 and not forced and not remaining and not left, name

def shared(name):
    p = subprocess.run(['docker', '--context', 'orbstack', 'ps', '-a', '--no-trunc',
                        '--format', '{{json .}}'], capture_output=True, text=True, timeout=15)
    (OUT / (name + '.json')).write_text(json.dumps({'exit': p.returncode, 'stdout': p.stdout, 'stderr': p.stderr}))
    p.check_returncode()
    return sorted((json.loads(row)['ID'], json.loads(row)['State']) for row in p.stdout.splitlines())

before = shared('shared-before') if MODE == 'application' else None
try:
    if MODE == 'full':
        run('build', 180, ['zig', 'build'], ROOT / 'toolchain')
        run('test', 900, ['zig', 'build', 'test', '--summary', 'all'], ROOT / 'toolchain')
    else:
        run('local', 60, ['python3', '-B', '-m', 'unittest', 'discover', '-s', EXECUTOR, '-p', 'test_*.py'])
        run('policy', 60, ['python3', '-B', APP / 'test_policy.py'])
        run('package-unit', 60, ['python3', '-B', APP / 'test_package.py'])
        package = OUT / ('lead-package-' + OUT.name)
        run('package', 720, ['python3', '-B', APP / 'build_image.py', package, ARCHIVE])
        image = (package / 'image.id').read_text().strip()
        manifest = hashlib.sha256((package / 'package-manifest.json').read_bytes()).hexdigest()
        assert manifest == MANIFEST, manifest
        (OUT / 'package-identity.json').write_text(json.dumps({'image': image, 'manifest': manifest,
            'matches_worker_manifest': True, 'image_reproducibility_claimed': False}, indent=2))
        run('application', 600, ['python3', '-B', APP / 'controls.py', OUT / ('lead-controls-' + OUT.name),
            '--image', image, '--toolchain', manifest])
        run('workspace', 600, ['python3', '-B', EXECUTOR / 'test_workspace_live.py', OUT / 'workspace-live'])
        run('executor', 600, ['python3', '-B', EXECUTOR / 'selftest.py', OUT / 'executor-live'])
        run('lifecycle', 120, ['python3', '-B', EXECUTOR / 'test_lifecycle_live.py', OUT / 'lifecycle-live'])
        run('extra', 240, ['python3', '-B', HERE / 'lead-controls.py', OUT / 'extra', image, manifest])
        run('final', 60, ['python3', '-B', HERE / 'inventory.py', OUT])
finally:
    changed = [p for p, digest in baseline.items() if hashlib.sha256((ROOT / p).read_bytes()).hexdigest() != digest]
    (OUT / 'source-after.json').write_text(json.dumps({'files': len(baseline), 'changed': changed,
        'tracked_bytes_unchanged': not changed}, indent=2))
    if before is not None:
        after = shared('shared-after')
        (OUT / 'shared-comparison.json').write_text(json.dumps({'before': before, 'after': after,
            'unchanged': before == after}, indent=2))
        assert before == after
    assert not changed, changed
