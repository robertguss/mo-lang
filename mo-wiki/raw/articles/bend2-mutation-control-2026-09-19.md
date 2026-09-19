---
source_url: https://github.com/bendlang/bend/tree/15ae0c86f3193b8f645b4bedbc438655b648d0da/demos/proof_insertion_sort
ingested: 2026-09-19
sha256: 009373bf5554a40706f6c2150497c1792007d3e20f7b9eae996075ded2f15db5
---
# Bend2 changed-implementation control — supplementary local evidence

The original sort proof passes. A scratch-copy sort changed to return Nil for every input rejects the old proof. The observed first failure is LAWS.sort_sorted (its proof no longer has the expected shape), NOT an observed failure specifically at the count-preservation law. This shows old-proof invalidation for this change, not a universal soundness result or a claim that proof repair is impossible under every specification. The upstream source and Mo implementation remain unchanged.

## Exact supplementary output

```json
[
  {
    "label": "bend-version",
    "command": [
      "/home/exedev/.hermes/profiles/mo-auditor/mo-research/bend-tools/node_modules/@oven/bun-linux-x64/bin/bun",
      "/home/exedev/.hermes/profiles/mo-auditor/workspace/bend-research/bend2/main.ts",
      "--version"
    ],
    "exit": 0,
    "stdout": "bend 2.0.16\n",
    "stderr": "",
    "seconds": 0.019136518007144332
  },
  {
    "label": "sort-laws-proof",
    "command": [
      "/home/exedev/.hermes/profiles/mo-auditor/mo-research/bend-tools/node_modules/@oven/bun-linux-x64/bin/bun",
      "/home/exedev/.hermes/profiles/mo-auditor/workspace/bend-research/bend2/main.ts",
      "demos/proof_insertion_sort/PROOF.bend"
    ],
    "exit": 0,
    "stdout": "All terms check.\n",
    "stderr": "",
    "seconds": 0.21293315012007952
  },
  {
    "label": "sort-drop-input",
    "command": [
      "/home/exedev/.hermes/profiles/mo-auditor/mo-research/bend-tools/node_modules/@oven/bun-linux-x64/bin/bun",
      "/home/exedev/.hermes/profiles/mo-auditor/workspace/bend-research/bend2/main.ts",
      "/tmp/bend-research-61oig87d/sort/PROOF.bend"
    ],
    "exit": 1,
    "stdout": "",
    "stderr": "Error:\n- expected : Unit\n- observed : Sigma<&1, &1, Unit, _ => Unit>\nContext:\n- h : Nat\n- t : List<&2, Nat>\nLocation: LAWS.sort_sorted\n38 |     case h <> t:\n39>|       sorted_ins(Sort.sort(t), 0n, h)(Laws.sort_sorted(t), Unit{})\n40 | \n",
    "seconds": 0.23553323186933994
  }
]
```

## Extended reproduction script

```python
"""Bounded Bend2 design-research smoke checks; no network/cluster gates.
Usage: python3 bend-smoke.py REPO BUN ZIG OUTPUT_JSON
Scratch copies only; neither Bend nor Mo source is edited.
"""
import json, os, pathlib, shutil, subprocess, sys, tempfile, time
repo, bun, zig, out = map(pathlib.Path, sys.argv[1:])
repo=repo.resolve(); results=[]
env=dict(os.environ,BEND_NO_TELEMETRY='1')
def run(label,args,timeout=40,cwd=None):
    start=time.monotonic()
    try:
        p=subprocess.run(list(map(str,args)),cwd=cwd or repo,env=env,text=True,capture_output=True,timeout=timeout)
        record=dict(label=label,command=list(map(str,args)),exit=p.returncode,stdout=p.stdout,stderr=p.stderr)
    except subprocess.TimeoutExpired as e:
        record=dict(label=label,command=list(map(str,args)),exit='timeout',stdout=str(e.stdout or ''),stderr=str(e.stderr or ''))
    record['seconds']=time.monotonic()-start; results.append(record)
    out.write_text(json.dumps(results,indent=2)+'\n')
    print(json.dumps({**record, 'stdout': record['stdout'][:500]}),flush=True)
    return record
cli=[bun,repo/'bend2/main.ts']
run('bun-version',[bun,'--version'])
run('bend-version',cli+['--version'])
run('sort-laws-proof',cli+['demos/proof_insertion_sort/PROOF.bend'])
run('sort-evaluate',cli+['demos/proof_insertion_sort/main.bend'])
run('base-discovery',cli+['base','Map'])
with tempfile.TemporaryDirectory(prefix='bend-research-') as d:
    d=pathlib.Path(d)
    shutil.copytree(repo/'demos/proof_insertion_sort',d/'sort')
    # A plausible but wrong implementation: every output is sorted, but elements disappear.
    source=(d/'sort/main.bend').read_text()
    old='def sort(xs: List<&2, Nat>) -> List<&2, Nat>:\n  match xs:\n    case Nil{}:\n      Nil{}\n    case h <> t:\n      insert(h, sort(t))'
    assert old in source
    (d/'sort/main.bend').write_text(source.replace(old,'def sort(xs: List<&2, Nat>) -> List<&2, Nat>:\n  Nil{}'))
    run('sort-drop-input',cli+[d/'sort/PROOF.bend'])
    (d/'sort/main.bend').write_text(source)
    # Only the copied proof is replaced: exact original laws and implementation retained.
    (d/'sort/PROOF.bend').write_text('import ./LAWS.bend as Laws\n')
    run('open-claims',cli+[d/'sort/PROOF.bend'])
    (d/'sort/PROOF.bend').write_text('import Base\n')
    run('missing-laws-import',cli+[d/'sort/PROOF.bend'])
    false=d/'false.bend'
    false.write_text('import Base\nlaw wrong:\n  {0n == 1n : Nat}\ndef wrong():\n  {==}\n')
    run('false-equality',cli+[false])
    js=d/'sort.js'; c=d/'sort.c'; binary=d/'sort-bin'
    if run('emit-js',cli+['demos/proof_insertion_sort/main.bend','-o',js])['exit']==0:
        run('run-js',['node',js])
    if run('emit-c',cli+['demos/proof_insertion_sort/main.bend','-o',c])['exit']==0:
        # C backend smoke using available Zig's C driver, not Bend's Clang-discovery route.
        if run('compile-c-zig',[zig,'cc','-O2',c,'-lpthread','-lm','-o',binary],timeout=120)['exit']==0:
            run('run-c',[binary,'--threads','1'])
```
