"""Bounded step-36 auditor checks; run from this checkout. No engineering edits.
Requires uv; installs/runs pinned ziglang 0.16.0 in uv's tool cache.
The ordering check uses explicitly mocked I/O, not TLS evidence.
"""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent
BENCH = ROOT / 'toolchain/bench/step36'
results = []

def command(label, argv, cwd=ROOT, timeout=180, env=None):
    r = subprocess.run(argv, cwd=cwd, env=env, capture_output=True, text=True, timeout=timeout)
    results.append({'check': label, 'command': list(map(str, argv)), 'returncode': r.returncode,
                    'stdout': r.stdout, 'stderr': r.stderr})
    print(label, 'exit', r.returncode, flush=True)
    return r

try:
    z = command('locate pinned Zig', ['uv', 'tool', 'run', '--from', 'ziglang==0.16.0', 'python', '-c',
        'import ziglang,pathlib; print(pathlib.Path(ziglang.__file__).parent)'])
    assert z.returncode == 0
    env = dict(os.environ)
    env['PATH'] = z.stdout.strip() + os.pathsep + env['PATH']
    zig = str(Path(z.stdout.strip()) / 'zig')
    command('TLS native tests', [zig, 'test', 'src/bricks/tls.zig'], ROOT / 'toolchain', env=env)
    command('build interpreter', [zig, 'build'], ROOT / 'toolchain', env=env)
    mo = str(ROOT / 'toolchain/zig-out/bin/mo')
    command('example format', [mo, 'fmt', '--check', 'examples/effects/tls-echo.mo'], env=env)
    command('example tests', [mo, 'test', 'examples/effects/tls-echo.mo'], env=env)
    command('example run from corpus cwd', [mo, 'run', 'tls-echo.mo', '--', '18443'], ROOT / 'examples/effects', env=env)
    command('abuse both runtimes', [sys.executable, 'abuse.py'], BENCH, timeout=240, env=env)
    sys.path.insert(0, str(BENCH))
    import abuse
    events = []
    class Server:
        port = 12345
        def alive(self): return True
        def stop(self): pass
    def raw(port, payload, wait):
        if payload.startswith(b'GET'): name, answer = 'http', ('alert', 10, 0)
        elif not payload: name, answer = 'silent', ('closed', None, 10)
        elif payload[3:5] == b'\xff\xff': name, answer = 'oversized', ('alert', 22, 0)
        else: name, answer = 'truncated', ('closed', None, 10)
        events.append(name)
        return answer
    def client(port, extra):
        name, number = ('tls1_2', 70) if '-tls1_2' in extra else ('p256only', 40)
        events.append(name)
        return f'alert number {number}'
    def echo(port, suite, key, text, **kw):
        events.append('health' if text == b'after\n' else 'retry')
        return text
    with patch.object(abuse, 'raw_case', raw), patch.object(abuse, 's_client_case', client), \
         patch.object(abuse.common, 'echo_once', echo), patch.object(abuse.common, 'start_echo', lambda *a: Server()), \
         patch.object(sys, 'argv', ['abuse.py', '--runtimes', 'run']):
        abuse.main()
    assert events[:7] == ['http','tls1_2','p256only','truncated','silent','oversized','retry']
    assert events[7:] == ['health'] * 7
    results.append({'check': 'MOCKED abuse ordering', 'events': events,
                    'observation': 'All cases execute before any of the seven health checks.'})
finally:
    (HERE / 'auditor-checks.json').write_text(json.dumps(results, indent=2) + '\n')
