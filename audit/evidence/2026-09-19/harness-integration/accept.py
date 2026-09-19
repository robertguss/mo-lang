"""Lead-only guarded acceptance; each invocation retains a fresh attempt."""
from datetime import datetime
import json
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


(OUT / 'integrated-commit.txt').write_text(subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True))
if MODE == 'provider-setup':
    checks = [('setup', 180, ['python3', PROVIDER / 'setup.py'])]
elif MODE == 'provider-clean':
    checks = [('clean-setup', 1200, ['python3', PROVIDER / 'clean_setup.py', OUT / 'clean'])]
elif MODE == 'provider-test':
    copy = Path(json.loads((HERE / sys.argv[3] / 'clean/commands.json').read_text())[0]['cwd'])
    checks = [
        ('parser', 600, ['python3', copy / 'run.py', '550', 'node', 'test.mjs', OUT / 'outbound.json']),
        ('lead-controls', 60, ['python3', copy / 'run.py', '50', 'node', HERE / 'provider-controls.mjs', copy, OUT / 'lead-controls.json']),
    ]
elif MODE == 'executor':
    before = shared_snapshot('shared-before')
    checks = [
        ('unit', 60, ['python3', '-B', EXECUTOR / 'test_executor.py']),
        ('live', 600, ['python3', '-B', EXECUTOR / 'selftest.py', OUT / 'live']),
        ('lifecycle', 120, ['python3', '-B', EXECUTOR / 'test_lifecycle_live.py', OUT / 'lifecycle']),
        ('lead-control', 60, ['python3', '-B', HERE / 'executor-control.py', OUT / 'lead-control']),
        ('final-state', 30, ['python3', '-B', EXECUTOR / 'evidence/final_lifecycle_check.py']),
    ]
else:
    raise ValueError(MODE)
ok = True
try:
    for check in checks:
        if not run(*check):
            ok = False
            break
finally:
    if MODE == 'executor':
        after = shared_snapshot('shared-after')
        inventory = {'before': before, 'after': after, 'unchanged': before == after}
        (OUT / 'shared-comparison.json').write_text(json.dumps(inventory, indent=2) + '\n')
        ok = ok and before == after
raise SystemExit(not ok)
