"""Focused unmodified TLS echo comparisons after retained full-suite mismatch."""
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[4]
OUT = ROOT / 'audit/evidence/2026-09-19/application' / sys.argv[1]
OUT.mkdir(exist_ok=False)
SOURCE = ROOT / 'examples/effects/tls-echo.mo'
MO = ROOT / 'toolchain/zig-out/bin/mo'
GUARD = ROOT / 'toolchain/bench/step36/guard.py'
before = hashlib.sha256(SOURCE.read_bytes()).hexdigest()
records = []

def run(name, argv, cwd, seconds=10):
    command = ['python3', str(GUARD), str(seconds), '--', *map(str, argv)]
    start = time.monotonic()
    p = subprocess.Popen(command, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
    try:
        stdout, stderr = p.communicate(timeout=seconds + 5)
    finally:
        try:
            os.killpg(p.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        p.wait(timeout=5)
    record = {'name': name, 'argv': command, 'cwd': str(cwd), 'exit': p.returncode,
              'stdout': stdout.decode(), 'stderr': stderr.decode(), 'elapsed': time.monotonic() - start}
    records.append(record)
    (OUT / 'records.json').write_text(json.dumps(records, indent=2))
    print(json.dumps(record), flush=True)
    assert p.returncode == 0, name
    return record

run('build', [MO, 'build', SOURCE, '-o', 'tls-echo'], OUT, 180)
binary = OUT / 'zig-out/mo-build/tls-echo/tls-echo'
assert binary.is_file()
expected = 'listening on 18443\nserved 0 connections, then went quiet\n'
for n in range(5):
    for kind, command in [('interpreter', [MO, 'run', 'tls-echo.mo', '--', '18443']), ('native', [binary, '18443'])]:
        r = run(kind + '-' + str(n + 1), command, SOURCE.parent)
        assert r['stdout'] == expected and r['stderr'] == '', r
assert before == hashlib.sha256(SOURCE.read_bytes()).hexdigest()
(OUT / 'summary.json').write_text(json.dumps({'passed': 10, 'expected': 10,
    'source_sha256': before, 'source_unchanged': True, 'intentional_clients': 0}, indent=2))
