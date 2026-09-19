"""Lead-only guarded acceptance; each invocation retains a fresh attempt."""
from datetime import datetime
import json
import hashlib
import shutil
import tempfile
import os
from pathlib import Path
import signal
import subprocess
import sys
import time
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent
MODE = sys.argv[1]
OUT = HERE / sys.argv[2]
OUT.mkdir(exist_ok=False)
GUARD = ROOT / 'toolchain/bench/step36/guard.py'
PROVIDER = ROOT / 'toolchain/harness/provider'
EXECUTOR = ROOT / 'toolchain/harness/executor'


def members(pgid):
    rows = subprocess.check_output(['ps', '-axo', 'pid=,pgid=,command='], text=True).splitlines()
    return [r.strip() for r in rows if len(r.split(None, 2)) == 3 and r.split(None, 2)[1] == str(pgid)]


def run(name, seconds, args):
    argv = ['python3', str(GUARD), str(seconds), '--', *map(str, args)]
    started = datetime.now(ZoneInfo('America/New_York')).isoformat()
    with (OUT / (name + '.stdout.txt')).open('w') as out, (OUT / (name + '.stderr.txt')).open('w') as err:
        p = subprocess.Popen(argv, cwd=ROOT, stdout=out, stderr=err, start_new_session=True)
        forced = False
        try:
            rc = p.wait(timeout=seconds + 15)
        except subprocess.TimeoutExpired:
            forced = True
            os.killpg(p.pid, signal.SIGKILL)
            rc = p.wait(timeout=3)
        before = members(p.pid)
        if before:
            os.killpg(p.pid, signal.SIGKILL)
            time.sleep(1)
        after = members(p.pid)
    record = dict(command=argv, cwd=str(ROOT), started_et=started,
                  finished_et=datetime.now(ZoneInfo('America/New_York')).isoformat(),
                  exit_code=rc, forced=forced, cleanup_before=before, cleanup_after=after)
    (OUT / (name + '.status.json')).write_text(json.dumps(record, indent=2) + '\n')
    print(json.dumps({'check': name, **record}), flush=True)
    return rc == 0 and not forced and not before and not after


def shared_snapshot(name):
    # Explicit read-only endpoint. Candidate execution never uses this daemon.
    p = subprocess.run(['docker', '--context', 'orbstack', 'ps', '-a', '--no-trunc', '--format', '{{json .}}'],
                       capture_output=True, text=True, timeout=15)
    (OUT / (name + '.jsonl')).write_text(p.stdout)
    (OUT / (name + '.stderr.txt')).write_text(p.stderr)
    (OUT / (name + '.exit')).write_text(str(p.returncode) + '\n')
    p.check_returncode()
    return sorted((json.loads(line)['ID'], json.loads(line)['State']) for line in p.stdout.splitlines())


worker = '2a6360c1f17feb1132ff6c77127d4057d71969dd'
base = '54c3dcd8617c8d693fddee8efda99e03ac05e879'
paths = subprocess.check_output(['git', 'diff', '--name-only', base, worker], cwd=ROOT, text=True).splitlines()
assert all(p.startswith('toolchain/harness/provider/auth/') for p in paths)
for p in paths:
    assert (ROOT / p).read_bytes() == subprocess.check_output(['git', 'show', worker + ':' + p], cwd=ROOT), p
tracked = subprocess.check_output(['git', 'ls-files', 'toolchain/harness/provider'], cwd=ROOT, text=True).splitlines()
before = {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in tracked}
copy = Path(tempfile.mkdtemp(prefix='lead-auth-', dir=PROVIDER / '.cache'))
for p in PROVIDER.iterdir():
    if p.is_file(): shutil.copy2(p, copy / p.name)
shutil.copytree(PROVIDER / 'evidence', copy / 'evidence')
for p in paths:
    target = copy / Path(p).relative_to('toolchain/harness/provider')
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(ROOT / p, target)
auth = copy / 'auth'
source = PROVIDER / '.cache/clean-setup-8f3xpo0r'
controls = (auth / 'controls.txt').read_text().split()
assert len(controls) == 28 and len(set(controls)) == 28
(OUT / 'source-identity.json').write_text(json.dumps({'worker': worker, 'integrated': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(), 'exact_worker_files': len(paths), 'copy': str(copy), 'prior_prepared_source': str(source), 'passed': True}, indent=2) + '\n')
checks = [
    ('setup', 600, ['python3', auth / 'run.py', 'lead-setup', 'python3', 'setup.py', source, 'prepared']),
    ('auth', 600, ['python3', auth / 'run.py', 'lead-auth', 'node', 'test.mjs', '.cache/prepared/.cache/runtime', *controls]),
    ('foundation', 600, ['python3', auth / 'run.py', 'lead-foundation', 'python3', '.cache/prepared/run.py', '500', 'node', 'test.mjs', 'evidence/lead-auth.outbound.json']),
    ('extra', 60, ['python3', auth / 'run.py', 'lead-extra', 'node', HERE / 'lead-controls.mjs', auth / 'auth.mjs']),
]
ok = True
try:
    for check in checks:
        if not run(*check):
            ok = False
            break
finally:
    retained = OUT / 'copy-evidence'
    retained.mkdir()
    for name in ['lead-setup','lead-auth','lead-foundation','lead-extra']:
        directory = auth / 'evidence' / name
        if directory.exists(): shutil.copytree(directory, retained / name)
    changed = [p for p in before if hashlib.sha256((ROOT / p).read_bytes()).hexdigest() != before[p]]
    copied = [p for p in paths if (ROOT / p).read_bytes() != (copy / Path(p).relative_to('toolchain/harness/provider')).read_bytes()]
    (OUT / 'source-after.json').write_text(json.dumps({'files': len(before), 'original_tracked_bytes_unchanged': not changed, 'changed': changed, 'copied_worker_bytes_unchanged': not copied, 'copied_changed': copied}, indent=2) + '\n')
    ok = ok and not changed and not copied
raise SystemExit(not ok)
