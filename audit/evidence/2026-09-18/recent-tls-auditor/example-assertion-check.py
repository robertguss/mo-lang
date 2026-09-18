"""Labelled mutation/control-flow check, NOT a TLS implementation change.
A temporary copy of the example makes tried() return Timeout without creating
any TLS connection. Run its unchanged six tests through mo test.
"""
from pathlib import Path
import subprocess
import tempfile
ROOT = Path(__file__).resolve().parents[4]
source = (ROOT / 'examples/effects/tls-client.mo').read_text()
start = source.index('  server = try tls.server', source.index('fn tried('))
end = source.index('\nend', start)
mutant = (source[:start] + '  Error(Timeout)' + source[end:]).split('\nverified:')[0] + '\n'
with tempfile.TemporaryDirectory() as d:
    p = Path(d) / 'tls-client.mo'
    p.write_text(mutant)
    run = subprocess.run([str(ROOT / 'toolchain/zig-out/bin/mo'), 'test', str(p)], text=True, capture_output=True, timeout=90)
    print('MUTATED TEMPORARY COPY: tried() unconditionally Error(Timeout), no handshake or echo')
    print('exit:', run.returncode)
    print((run.stdout + run.stderr).rstrip())
