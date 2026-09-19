import json
from run import ROOT, invoke
failed = False
for args in [['zig','build'],['zig','build','test','--summary','all']]:
    evidence = invoke(args, 570, ROOT/'toolchain')
    print(json.dumps(evidence), flush=True)
    failed |= evidence['exit_code'] != 0
raise SystemExit(int(failed))
