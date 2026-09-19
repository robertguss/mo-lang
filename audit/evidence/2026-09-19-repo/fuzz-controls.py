"""MOCKED accounting/argument checks only. No TLS engine or real fuzzing.
Run from anywhere: python3 audit/evidence/2026-09-19-repo/fuzz-controls.py
"""
import contextlib
import io
import json
import pathlib
import sys
import tempfile
import types
from unittest.mock import patch
ROOT = pathlib.Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'toolchain/bench/step37'))
import fuzz


def check(minutes, failed_batch=False):
    with tempfile.TemporaryDirectory() as d:
        work = pathlib.Path(d)
        def record(*args, **kwargs):
            dest = pathlib.Path(kwargs['env']['MO_FUZZ_RECORD'])
            for i in range(16):
                (dest / ('case-%02d.bin' % i)).write_bytes(b'MOFZ\x00')
            return types.SimpleNamespace(returncode=0, stdout='', stderr='')
        returns = iter([(134, 'mock panic'), (3, 'mock hang')] + ([(134, 'MOCK BATCH FAILURE'), (0, ''), (0, '')] if failed_batch else []))
        calls = []
        def run(*args):
            rc, text = next(returns)
            calls.append({'exit':rc,'output':text})
            return rc, text
        output = io.StringIO()
        with patch.object(fuzz.c, 'WORK', work), patch.object(fuzz.c, 'ensure_tools', lambda: None), patch.object(fuzz.subprocess, 'run', record), patch.object(fuzz, 'run', run), patch.object(fuzz, 'cpu_seconds', side_effect=[0,0,1,1]), patch.object(fuzz, 'mutate', lambda *a: (b'MOFZ\x00',['mock'])), patch.object(fuzz.c, 'stamp', lambda:'MOCKED date/load\n'), patch.object(sys, 'argv', ['fuzz.py','--seed','1','--minutes',minutes,'--batch','2']), contextlib.redirect_stdout(output):
            rc = fuzz.main()
        retained = sorted(p.relative_to(work).as_posix() for p in (work/'fuzz-1'/'failed-batches').rglob('*') if p.is_file())
        return {'minutes':minutes,'returncode':rc,'calls':calls,'retained':retained,'output':output.getvalue()}

results=[check('.001',True),check('0'),check('-1'),check('nan')]
assert results[0]['returncode']==1 and len(results[0]['retained'])==3
for r in results[1:]:
    assert r['returncode']==0 and '0 inputs in 0 batches' in r['output'] and len(r['calls'])==2
print(json.dumps({'kind':'MOCKED harness control flow, not TLS fuzz results','results':results},indent=2))
