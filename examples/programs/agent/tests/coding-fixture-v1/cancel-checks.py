import json, sys
from run import ROOT, HERE, MO, invoke
commands = [
 [MO,'fmt',str(HERE/'boundaries.mo')],
 [MO,'test','--write','--sim','100',str(HERE/'boundaries.mo')],
 [MO,'build',str(HERE/'boundaries.mo'),'-o','coding-fixture-cancel'],
 [sys.executable,str(HERE/'cancel.py'),'interpreter'],
 [sys.executable,str(HERE/'cancel.py'),'compiled'],
 [MO,'build','--tests',str(HERE/'boundaries.mo'),'-o','coding-fixture-test-boundaries'],
 [str(ROOT/'zig-out/mo-build/coding-fixture-test-boundaries/coding-fixture-test-boundaries')],
]
failed=False
for command in commands:
    evidence=invoke(command,120)
    print(json.dumps(evidence),flush=True)
    failed |= evidence['exit_code']!=0
raise SystemExit(int(failed))
