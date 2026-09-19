"""Sequential existing live regressions, output confined to recovery evidence."""
import json
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
root = Path(sys.argv[1])
root.mkdir(parents=True, exist_ok=False)
records = []
for name, script in [('workspace22','test_workspace_live.py'),('executor17','selftest.py'),('lifecycle1','test_lifecycle_live.py')]:
    args = [sys.executable,'-B',str(HERE.parent / script),str(root / name)]
    with (root / (name+'.log')).open('xb') as out:
        p = subprocess.run(args,stdout=out,stderr=subprocess.STDOUT,timeout=600)
    records.append({'name':name,'argv':args,'exit':p.returncode})
    (root / 'exits.json').write_text(json.dumps(records,indent=2))
    print(name,p.returncode,flush=True)
    if p.returncode:
        sys.exit(p.returncode)
# Existing application controls, with only their generated cache redirected into
# this owned evidence directory. Source/control bodies remain unchanged.
sys.path.insert(0, str(HERE.parent / 'application'))
import controls
original_load = controls.load
controls.load = lambda _: original_load(root / 'application-source-cache')
from live import IMAGE, TOOLCHAIN
with (root / 'application23.log').open('x') as out:
    import contextlib
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(out):
        controls.run(str(root / 'application23'),IMAGE,TOOLCHAIN,list(controls.CONTROLS))
records.append({'name':'application23','exit':0})
(root / 'exits.json').write_text(json.dumps(records,indent=2))
print('application23',0,flush=True)
