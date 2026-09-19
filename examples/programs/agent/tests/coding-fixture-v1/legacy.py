import json, shutil, tempfile
from pathlib import Path
from run import ROOT, MO, invoke
failed = False
for mode in ['interpreter','compiled']:
    with tempfile.TemporaryDirectory(prefix='mo-legacy-') as tmp:
        directory = Path(tmp)
        shutil.copytree(ROOT/'examples/programs/agent/data', directory/'data')
        prefix = [MO,'run',str(ROOT/'examples/programs/agent/main.mo'),'--'] if mode=='interpreter' else [str(ROOT/'zig-out/mo-build/coding-fixture/coding-fixture')]
        cases = [(['check','data/demo','data/script.txt','data/runs.txt'],0),
                 (['run','data/solo','--model','127.0.0.1:1','--folder','work','say','what','the','folder','holds'],3),
                 (['mock','data/nowhere.txt'],1),(['serve'],2),
                 (['serve','data/nowhere','--model','127.0.0.1:1'],1),
                 (['client','127.0.0.1','1','ada','GET','/runs'],1)]
        for i,(args,code) in enumerate(cases,1):
            evidence = invoke(prefix+args, 60, directory)
            expected = ROOT/'examples/programs/agent'/('agent'+('' if i==1 else '-'+str(i))+'.expected')
            evidence.update(mode=mode, fixture=i, expected_exit=code,
                            passed=evidence['exit_code']==code and evidence['stdout']==expected.read_text())
            print(json.dumps(evidence),flush=True)
            failed |= not evidence['passed']
raise SystemExit(int(failed))
