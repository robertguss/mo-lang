"""Format owned sources, regenerate dependency evidence, build and run native checks."""
import json
import sys
from run import ROOT, MO, invoke
OWNED = ['exact-edit','command-adapter','report','record','tools','steps','run','registry','coding-fixture','main','tests/coding-fixture-v1/boundaries']
ORDER = ['exact-edit','command-adapter','record','report','transcript','shelf','api','filing','book','tools','steps','run','registry','coding-fixture','server','check','main','runs','tests/coding-fixture-v1/boundaries']
SIM = ['book','tools','run','server','runs']
failed = False

def run(label, command, seconds=180):
    global failed
    evidence = invoke(command, seconds)
    evidence['check'] = label
    print(json.dumps(evidence), flush=True)
    failed |= evidence['exit_code'] != 0
    return evidence['exit_code'] == 0

for name in OWNED:
    run('fmt-'+name, [MO,'fmt','examples/programs/agent/'+name+'.mo'])
for name in ORDER:
    run('write-'+name, [MO,'test','--write','examples/programs/agent/'+name+'.mo']+(['--sim','100'] if name in SIM else ['--sim','100'] if name.endswith('/boundaries') else []))
if failed: sys.exit(1)
run('model-conformance', [MO,'check','examples/programs/agent/model.mo'])
if not run('build-agent', [MO,'build','examples/programs/agent/main.mo','-o','coding-fixture']):
    sys.exit(1)
run('legacy-cli', [sys.executable, str(ROOT/'examples/programs/agent/tests/coding-fixture-v1/legacy.py')], 120)
for name in ['tests/coding-fixture-v1/boundaries','main','record','tools','steps','run','registry','transcript']:
    binary = 'coding-fixture-test-'+name.split('/')[-1]
    if run('build-tests-'+name,[MO,'build','--tests','examples/programs/agent/'+name+'.mo','-o',binary]):
        run('native-tests-'+name,[str(ROOT/'zig-out/mo-build'/binary/binary)])
sys.exit(int(failed))
