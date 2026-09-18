"""MOCKED harness control-flow only; this is not a real TLS fuzz result.
Inject a failed batch whose individual replays all succeed. Test whether the
original script retains the batch failure in its reported crash count.
"""
import pathlib
import sys
import tempfile
import types
from unittest.mock import patch
ROOT = pathlib.Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / 'toolchain/bench/step37'))
import fuzz

with tempfile.TemporaryDirectory() as d:
    work = pathlib.Path(d)
    def record(*args, **kwargs):
        dest = pathlib.Path(kwargs['env']['MO_FUZZ_RECORD'])
        for i in range(16):
            (dest / ('case-%02d.bin' % i)).write_bytes(b'MOFZ\x00')
        return types.SimpleNamespace(returncode=0, stdout='', stderr='')
    returns = iter([(134, 'mock panic'), (3, 'mock hang'), (134, 'MOCK BATCH FAILURE'), (0, ''), (0, '')])
    def run(*args):
        rc, text = next(returns)
        print('MOCK invocation exit:', rc, text)
        return rc, text
    with patch.object(fuzz.c, 'WORK', work), patch.object(fuzz.c, 'ensure_tools', lambda: None), patch.object(fuzz.subprocess, 'run', record), patch.object(fuzz, 'run', run), patch.object(fuzz, 'cpu_seconds', side_effect=[0, 0, 1, 1]), patch.object(fuzz, 'mutate', lambda *a: (b'MOFZ\x00', ['mock'])), patch.object(fuzz.c, 'stamp', lambda: 'MOCKED date/load\n'), patch.object(sys, 'argv', ['fuzz.py', '--seed', '1', '--minutes', '.001', '--batch', '2']):
        fuzz.main()
    print('MOCKED report from unchanged fuzz.py:')
    print((work / 'fuzz-1.txt').read_text())
