"""Lead-only guarded acceptance; each invocation retains a fresh attempt."""
from datetime import datetime
import json
import hashlib
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


worker = 'd9444f0a76fb0a011aea8cea66a8de46cbe185f2'
base = '2fc1235bd1f44ae7897ed059ece8cb9b30ce307d'
paths = subprocess.check_output(['git', 'diff', '--name-only', base, worker], cwd=ROOT, text=True).splitlines()
for path in paths:
    assert (ROOT / path).read_bytes() == subprocess.check_output(['git', 'show', worker + ':' + path], cwd=ROOT), path
tracked = subprocess.check_output(['git', 'ls-files', 'toolchain/harness/executor'], cwd=ROOT, text=True).splitlines()
hashes = {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in tracked}
(OUT / 'source-identity.json').write_text(json.dumps({'worker': worker, 'integrated': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(), 'exact_worker_files': len(paths), 'passed': True}, indent=2) + '\n')
before = shared_snapshot('shared-before')
checks = [
    ('unit', 60, ['python3', '-B', '-m', 'unittest', 'discover', '-s', EXECUTOR, '-p', 'test_*.py']),
    ('workspace-live', 600, ['python3', '-B', EXECUTOR / 'test_workspace_live.py', OUT / 'workspace-live']),
    ('fixture-live', 600, ['python3', '-B', EXECUTOR / 'selftest.py', OUT / 'fixture-live']),
    ('lifecycle', 120, ['python3', '-B', EXECUTOR / 'test_lifecycle_live.py', OUT / 'lifecycle']),
    ('extra', 90, ['python3', '-B', HERE / 'lead-controls-v2.py', OUT / 'extra']),
    ('final-state', 30, ['python3', '-B', EXECUTOR / 'evidence/final_lifecycle_check.py']),
]
if MODE == 'workspace-extra':
    checks = [
        ('extra', 90, ['python3', '-B', HERE / 'lead-controls-v2.py', OUT / 'extra']),
        ('final-state', 30, ['python3', '-B', EXECUTOR / 'evidence/final_lifecycle_check.py']),
    ]
ok = True
try:
    for check in checks:
        if not run(*check):
            ok = False
            break
finally:
    after = shared_snapshot('shared-after')
    (OUT / 'shared-comparison.json').write_text(json.dumps({'before': before, 'after': after, 'unchanged': before == after}, indent=2) + '\n')
    changed = [p for p in hashes if hashlib.sha256((ROOT / p).read_bytes()).hexdigest() != hashes[p]]
    (OUT / 'source-after.json').write_text(json.dumps({'files': len(hashes), 'tracked_bytes_unchanged': not changed, 'changed': changed}, indent=2) + '\n')
    ok = ok and before == after and not changed
raise SystemExit(not ok)
