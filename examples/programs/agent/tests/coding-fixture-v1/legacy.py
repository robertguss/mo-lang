import json, os, shutil, tempfile
from pathlib import Path
from run import ROOT, MO, invoke
native = ROOT/'zig-out/mo-build/coding-fixture/coding-fixture'
if not native.is_file() or not os.access(native, os.X_OK):
    print(json.dumps(dict(check='native-executable', executable=str(native),
                          passed=False, error='native executable missing or not executable; run verify.py first')), flush=True)
    raise SystemExit(1)

# Exact legacy stderr goldens, paired with the existing stdout golden files.
expected_stderr = [
    'agent: 2 run logs copied into data/demo/runs.check, 1 left running there failed as restarted\n'
    'agent: 9 run logs removed from data/demo/runs.check\n',
    '',
    'agent: data/nowhere.txt is not a script agent can read\n',
    'agent: serve takes a folder; usage: agent serve <dir> --model host:port [--port N] [--surface PORT] | agent mock <script> [--port N] | agent run <dir> --model host:port <goal> [--tools a,b] [--folder p] | agent client <host> <port> <token> <method> <path> [<json>] | agent check <dir> <script> <runs>\n',
    'agent: data/nowhere cannot make its folder runs\n',
    'agent: no agent answered at 127.0.0.1:1\n',
]
failed = False
for mode in ['interpreter','compiled']:
    with tempfile.TemporaryDirectory(prefix='mo-legacy-') as tmp:
        directory = Path(tmp)
        shutil.copytree(ROOT/'examples/programs/agent/data', directory/'data')
        prefix = [MO,'run',str(ROOT/'examples/programs/agent/main.mo'),'--'] if mode=='interpreter' else [str(native)]
        cases = [(['check','data/demo','data/script.txt','data/runs.txt'],0),
                 (['run','data/solo','--model','127.0.0.1:1','--folder','work','say','what','the','folder','holds'],3),
                 (['mock','data/nowhere.txt'],1),(['serve'],2),
                 (['serve','data/nowhere','--model','127.0.0.1:1'],1),
                 (['client','127.0.0.1','1','ada','GET','/runs'],1)]
        for i,(args,code) in enumerate(cases,1):
            evidence = invoke(prefix+args, 60, directory)
            expected = ROOT/'examples/programs/agent'/('agent'+('' if i==1 else '-'+str(i))+'.expected')
            evidence.update(mode=mode, fixture=i, expected_exit=code,
                            expected_stderr=expected_stderr[i-1],
                            passed=evidence['exit_code']==code and evidence['stdout']==expected.read_text()
                            and evidence['stderr']==expected_stderr[i-1])
            print(json.dumps(evidence),flush=True)
            failed |= not evidence['passed']
raise SystemExit(int(failed))
