"""Retain bounded wiki lint and audit-script syntax checks; no product imports."""
import ast
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
ROOT = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent
out = HERE / sys.argv[1]
out.mkdir(exist_ok=False)
for name in ('accept.py', 'launch.py', 'lead-controls.py'):
    ast.parse((HERE/name).read_text(), filename=name)
argv = ['python3', '-B', str(ROOT/'toolchain/bench/step36/guard.py'), '30', '--',
        'python3', '-B', str(ROOT/'mo-wiki/tools/lint.py')]
with (out/'stdout.txt').open('xb') as stdout, (out/'stderr.txt').open('xb') as stderr:
    p = subprocess.Popen(argv,cwd=ROOT,stdout=stdout,stderr=stderr,start_new_session=True)
    try:
        code = p.wait(timeout=40)
    finally:
        try: os.killpg(p.pid,signal.SIGKILL)
        except ProcessLookupError: pass
        p.wait()
try:
    os.killpg(p.pid,0); remaining = True
except ProcessLookupError:
    remaining = False
record = {'argv':argv,'exit':code,'group':p.pid,'group_remaining':remaining,
          'audit_scripts_parsed':3}
(out/'receipt.json').write_text(json.dumps(record,indent=2)+'\n')
print(json.dumps(record))
assert not remaining
raise SystemExit(code)
