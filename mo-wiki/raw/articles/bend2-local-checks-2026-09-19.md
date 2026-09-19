---
source_url: https://github.com/bendlang/bend/tree/15ae0c86f3193b8f645b4bedbc438655b648d0da
ingested: 2026-09-19
sha256: e88278648f74ca30086afa4227c1bcf55eef4e91155d852afb488f7678aab0d0
---
# Bend2 local smoke checks — Hermes research

Bend commit: `15ae0c86f3193b8f645b4bedbc438655b648d0da`. Linux x86_64. Bun installed only in the auditor profile from @oven/bun-linux-x64, with npm lifecycle scripts disabled. BEND_NO_TELEMETRY=1. No installer, package publication, cluster gate, GPU, or live effect services run. CLI version 2.0.16. C output compiled with Zig 0.16.0 cc because Clang was not on PATH; this is not the documented Clang-discovery build path. Timings are single-run observations, not a benchmark.

Initial Node invocation refused because the CLI requires Bun. Initial false-law fixture had a syntax error; corrected to def wrong() before interpreting its semantic result. Both runs retained below.

## Reproduction script (final)

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

## Initial output (includes invalid false-law syntax)

```json
[
  {
    "label": "bun-version",
    "command": [
      "/home/exedev/.hermes/profiles/mo-auditor/mo-research/bend-tools/node_modules/@oven/bun-linux-x64/bin/bun",
      "--version"
    ],
    "exit": 0,
    "stdout": "1.4.2\n",
    "stderr": "",
    "seconds": 0.0019292100332677364
  },
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
    "seconds": 0.01898467307910323
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
    "seconds": 0.20045961812138557
  },
  {
    "label": "sort-evaluate",
    "command": [
      "/home/exedev/.hermes/profiles/mo-auditor/mo-research/bend-tools/node_modules/@oven/bun-linux-x64/bin/bun",
      "/home/exedev/.hermes/profiles/mo-auditor/workspace/bend-research/bend2/main.ts",
      "demos/proof_insertion_sort/main.bend"
    ],
    "exit": 0,
    "stdout": "[1n, 2n, 3n]\n",
    "stderr": "",
    "seconds": 0.1825379659421742
  },
  {
    "label": "base-discovery",
    "command": [
      "/home/exedev/.hermes/profiles/mo-auditor/mo-research/bend-tools/node_modules/@oven/bun-linux-x64/bin/bun",
      "/home/exedev/.hermes/profiles/mo-auditor/workspace/bend-research/bend2/main.ts",
      "base",
      "Map"
    ],
    "exit": 0,
    "stdout": "type Map<a, -V: Kind(a)> is Kind(a):\n  MTip{}\n  MLeaf{key: String, val: V}\n  MNode{pos: Nat, lo: Map<a, V>, hi: Map<a, V>}\n\ndef Map.bit.u(x: U32, k: Nat) -> Bool:\n  U32.is_ne(U32.and(U32.shrn(x, k), 1), 0)\n\ndef Map.bit.chr(c: Char, off: Nat) -> Char & Bool:\n  match c off:\n    case Chr{x} 0n:\n      (Chr{x}, True{})\n    case Chr{+x} 1n+b:\n      (Chr{x}, Map.bit.u(x, Nat.sub(31n, b)))\n\ndef Map.bit.go.chr(t: String, r: Char & Bool) -> String & Bool:\n  (c2, b) = r\n  (SCon{c2, t}, b)\n\ndef Map.bit.go.rec(c: Char, r: String & Bool) -> String & Bool:\n  (t2, b) = r\n  (SCon{c, t2}, b)\n\ndef Map.bit.go(key: String, ci: Nat, off: Nat) -> String & Bool:\n  match key:\n    case SNil{}:\n      (SNil{}, False{})\n    case SCon{c, t}:\n      match ci:\n        case 0n:\n          Map.bit.go.chr(t, Map.bit.chr(c, off))\n        case 1n+j:\n          Map.bit.go.rec(c, Map.bit.go(t, j, off))\n\ndef Map.bit.at(key: String, co: Nat & Nat) -> String & Bool:\n  (ci, off) = co\n  Map.bit.go(key, ci, off)\n\ndef Map.bit(key: String, pos: Nat) -> String & Bool:\n  Map.bit.at(key, Nat.divmod(pos, 33n))\n\nlaw Map.msb.u:\n  for n: Nat\n  for +x: U32\n  Nat\n\ndef Map.msb.u.if(p: Nat, x2: U32, z: Bool) -> Nat:\n  match z:\n    case True{}:\n      0n\n    case False{}:\n      Nat.add(1n, Map.msb.u(p, U32.shr(x2)))\n\ndef Map.msb.u(n, x):\n  match n:\n    case 0n:\n      0n\n    case 1n+p:\n      Map.msb.u.if(p, x, U32.is_zero(x))\n\ndef Map.diff.chr(x: U32) -> Nat:\n  Nat.sub(33n, Map.msb.u(32n, x))\n\ndef Map.diff.step(x: Char, y: Char) -> Nat & Bool:\n  match x y:\n    case Chr{+cx} Chr{+cy}:\n      (Map.diff.chr(U32.xor(cx, cy)), U32.is_eq(cx, cy))\n\nlaw Map.diff:\n  for a: String\n  for b: String\n  Nat\n\ndef Map.diff.fin(xt: String, yt: String, rc: Nat & Bool) -> Nat:\n  (r, c) = rc\n  match c:\n    case True{}:\n      Nat.add(33n, Map.diff(xt, yt))\n    case False{}:\n      r\n\ndef Map.diff(a, b):\n  match a b:\n    case SNil{} SNil{}:\n      0n\n    case SNil{} SCon{h, t}:\n      0n\n    case SCon{h, t} SNil{}:\n      0n\n    case SCon{x, xt} SCon{y, yt}:\n      Map.diff.fin(xt, yt, Map.diff.step(x, y))\n\ndef Map.new(a, -V: Kind(a)) -> Map<a, V>:\n  MTip{}\n\nlaw Map.put:\n  for -a  : Quant\n  for -V  : Kind(a)\n  for m   : Map<a, V>\n  for key : String\n  for x   : V\n  Map<a, V>\n\ndef Map.put.bit(\n  a, -V: Kind(a), x: V, p2: Nat, lo: Map<a, V>, hi: Map<a, V>, kb: String & Bool\n) -> Map<a, V>:\n  (key2, b) = kb\n  match b:\n    case False{}:\n      MNode{p2, Map.put(a, V, lo, key2, x), hi}\n    case True{}:\n      MNode{p2, lo, Map.put(a, V, hi, key2, x)}\n\ndef Map.put(a, V, m, key, x):\n  match m:\n    case MTip{}:\n      MLeaf{key, x}\n    case MLeaf{k, v}:\n      MLeaf{k, x}\n    case MNode{+pos, lo, hi}:\n      Map.put.bit(a, V, x, pos, lo, hi, Map.bit(key, pos))\n\ndef Map.ins.splice.bit(\n  a, -V: Kind(a), x: V, rest: Map<a, V>, pb: Nat, kb: String & Bool\n) -> Map<a, V>:\n  (key2, b) = kb\n  match b:\n    case False{}:\n      MNode{pb, MLeaf{key2, x}, rest}\n    case True{}:\n      MNode{pb, rest, MLeaf{key2, x}}\n\ndef Map.ins.splice(\n  a, -V: Kind(a), +p: Nat, key: String, x: V, rest: Map<a, V>\n) -> Map<a, V>:\n  Map.ins.splice.bit(a, V, x, rest, p, Map.bit(key, p))\n\nlaw Map.ins:\n  for -a  : Quant\n  for -V  : Kind(a)\n  for m   : Map<a, V>\n  for key : String\n  for x   : V\n  for +p  : Nat\n  Map<a, V>\n\ndef Map.ins.deep(\n  a, -V: Kind(a), x: V, lo: Map<a, V>, hi: Map<a, V>, pb: Nat, qb: Nat,\n  kb: String & Bool\n) -> Map<a, V>:\n  (key2, b) = kb\n  match b:\n    case False{}:\n      MNode{qb, Map.ins(a, V, lo, key2, x, pb), hi}\n    case True{}:\n      MNode{qb, lo, Map.ins(a, V, hi, key2, x, pb)}\n\ndef Map.ins.if(\n  a, -V: Kind(a), key: String, x: V, lo: Map<a, V>, hi: Map<a, V>, +p2: Nat,\n  pb: Nat, t: Bool\n) -> Map<a, V>:\n  match t:\n    case False{}:\n      Map.ins.splice(a, V, pb, key, x, MNode{p2, lo, hi})\n    case True{}:\n      Map.ins.deep(a, V, x, lo, hi, pb, p2, Map.bit(key, p2))\n\ndef Map.ins(a, V, m, key, x, p):\n  match m:\n    case MTip{}:\n      MLeaf{key, x}\n    case MLeaf{k, v}:\n      Map.ins.splice(a, V, p, key, x, MLeaf{k, v})\n    case MNode{+pos, lo, hi}:\n      Map.ins.if(a, V, key, x, lo, hi, pos, p, Nat.is_lt(pos, p))\n\ndef Map.lo(\n  a, -V: Kind(a), -R: Type, p2: Nat, hi: Map<a, V>, r0: Map<a, V> & R\n) -> Map<a, V> & R:\n  (lo2, r) = r0\n  (MNode{p2, lo2, hi}, r)\n\ndef Map.hi(\n  a, -V: Kind(a), -R: Type, p2: Nat, lo: Map<a, V>, r0: Map<a, V> & R\n) -> Map<a, V> & R:\n  (hi2, r) = r0\n  (MNode{p2, lo, hi2}, r)\n\nlaw Map.seek:\n  for -a  : Quant\n  for -V  : Kind(a)\n  for m   : Map<a, V>\n  for key : String\n  Map<a, V> & String & Maybe<&2, String>\n\ndef Map.seek.bit(\n  a, -V: Kind(a), lo: Map<a, V>, hi: Map<a, V>, p2: Nat, kb: String & Bool\n) -> Map<a, V> & String & Maybe<&2, String>:\n  (key2, b) = kb\n  match b:\n    case False{}:\n      Map.lo(a, V, String & Maybe<&2, String>, p2, hi, Map.seek(a, V, lo, key2))\n    case True{}:\n      Map.hi(a, V, String & Maybe<&2, String>, p2, lo, Map.seek(a, V, hi, key2))\n\ndef Map.seek(a, V, m, key):\n  match m:\n    case MTip{}:\n      (MTip{}, key, None{})\n    case MLeaf{+k, v}:\n      (MLeaf{k, v}, key, Some{k})\n    case MNode{+pos, lo, hi}:\n      Map.seek.bit(a, V, lo, hi, pos, Map.bit(key, pos))\n\ndef Map.set.fin.go(\n  a, -V: Kind(a), m: Map<a, V>, key: String, x: V, r: (String & String) & Cmp\n) -> Map<a, V>:\n  ((keyb2, k2), c) = r\n  match c:\n    case LT{}:\n      Map.ins(a, V, m, key, x, Map.diff(keyb2, k2))\n    case EQ{}:\n      Map.put(a, V, m, key, x)\n    case GT{}:\n      Map.ins(a, V, m, key, x, Map.diff(keyb2, k2))\n\ndef Map.set.fin(\n  a, -V: Kind(a), m: Map<a, V>, key: String, x: V, keyb: String, k: String\n) -> Map<a, V>:\n  Map.set.fin.go(a, V, m, key, x, String.cmp(keyb, k))\n\ndef Map.set.go(\n  a, -V: Kind(a), x: V, r: Map<a, V> & String & Maybe<&2, String>\n) -> Map<a, V>:\n  (m2, key2, found) = r\n  match found:\n    case None{}:\n      MLeaf{key2, x}\n    case Some{k}:\n      +ka = {key2 : String}\n      Map.set.fin(a, V, m2, ka, x, ka, k)\n\ndef Map.set(a, -V: Kind(a), m: Map<a, V>, key: String, x: V) -> Map<a, V>:\n  Map.set.go(a, V, x, Map.seek(a, V, m, key))\n\ndef Map.has.leaf(a, -V: Kind(a), v: V, r: (String & String) & Cmp) ->\n  Map<a, V> & Bool:\n  ((key2, k2), c) = r\n  (MLeaf{k2, v}, Cmp.is_eq(c))\n\nlaw Map.has:\n  for -a  : Quant\n  for -V  : Kind(a)\n  for m   : Map<a, V>\n  for key : String\n  Map<a, V> & Bool\n\ndef Map.has.bit(\n  a, -V: Kind(a), lo: Map<a, V>, hi: Map<a, V>, p2: Nat, kb: String & Bool\n) -> Map<a, V> & Bool:\n  (key2, b) = kb\n  match b:\n    case False{}:\n      Map.lo(a, V, Bool, p2, hi, Map.has(a, V, lo, key2))\n    case True{}:\n      Map.hi(a, V, Bool, p2, lo, Map.has(a, V, hi, key2))\n\ndef Map.has(a, V, m, key):\n  match m:\n    case MTip{}:\n      (MTip{}, False{})\n    case MLeaf{k, v}:\n      Map.has.leaf(a, V, v, String.cmp(key, k))\n    case MNode{+pos, lo, hi}:\n      Map.has.bit(a, V, lo, hi, pos, Map.bit(key, pos))\n\ndef Map.get.leaf(-V: Data, d: V, +v: V, r: (String & String) & Cmp) ->\n  Map<&2, V> & V:\n  ((key2, k2), c) = r\n  match c:\n    case LT{}:\n      (MLeaf{k2, v}, d)\n    case EQ{}:\n      (MLeaf{k2, v}, v)\n    case GT{}:\n      (MLeaf{k2, v}, d)\n\nlaw Map.get:\n  for -V  : Data\n  for d   : V\n  for m   : Map<&2, V>\n  for key : String\n  Map<&2, V> & V\n\ndef Map.get.bit(\n  -V: Data, d: V, lo: Map<&2, V>, hi: Map<&2, V>, p2: Nat, kb: String & Bool\n) -> Map<&2, V> & V:\n  (key2, b) = kb\n  match b:\n    case False{}:\n      Map.lo(&2, V, V, p2, hi, Map.get(V, d, lo, key2))\n    case True{}:\n      Map.hi(&2, V, V, p2, lo, Map.get(V, d, hi, key2))\n\ndef Map.get(V, d, m, key):\n  match m:\n    case MTip{}:\n      (MTip{}, d)\n    case MLeaf{k, v}:\n      Map.get.leaf(V, d, v, String.cmp(key, k))\n    case MNode{+pos, lo, hi}:\n      Map.get.bit(V, d, lo, hi, pos, Map.bit(key, pos))\n\ndef Map.pop.lo(\n  a, -V: Kind(a), pos: Nat, hi: Map<a, V>, r0: Map<a, V> & Maybe<a, V>\n) -> Map<a, V> & Maybe<a, V>:\n  (lo, r) = r0\n  match lo:\n    case MTip{}:\n      (hi, r)\n    case lo2:\n      (MNode{pos, lo2, hi}, r)\n\ndef Map.pop.hi(\n  a, -V: Kind(a), pos: Nat, lo: Map<a, V>, r0: Map<a, V> & Maybe<a, V>\n) -> Map<a, V> & Maybe<a, V>:\n  (hi, r) = r0\n  match hi:\n    case MTip{}:\n      (lo, r)\n    case hi2:\n      (MNode{pos, lo, hi2}, r)\n\ndef Map.pop.leaf(a, -V: Kind(a), v: V, r: (String & String) & Cmp) ->\n  Map<a, V> & Maybe<a, V>:\n  ((key2, k2), c) = r\n  match c:\n    case LT{}:\n      (MLeaf{k2, v}, None{})\n    case EQ{}:\n      (MTip{}, Some{v})\n    case GT{}:\n      (MLeaf{k2, v}, None{})\n\nlaw Map.pop:\n  for -a  : Quant\n  for -V  : Kind(a)\n  for m   : Map<a, V>\n  for key : String\n  Map<a, V> & Maybe<a, V>\n\ndef Map.pop.bit(\n  a, -V: Kind(a), lo: Map<a, V>, hi: Map<a, V>, p2: Nat, kb: String & Bool\n) -> Map<a, V> & Maybe<a, V>:\n  (key2, b) = kb\n  match b:\n    case False{}:\n      Map.pop.lo(a, V, p2, hi, Map.pop(a, V, lo, key2))\n    case True{}:\n      Map.pop.hi(a, V, p2, lo, Map.pop(a, V, hi, key2))\n\ndef Map.pop(a, V, m, key):\n  match m:\n    case MTip{}:\n      (MTip{}, None{})\n    case MLeaf{k, v}:\n      Map.pop.leaf(a, V, v, String.cmp(key, k))\n    case MNode{+pos, lo, hi}:\n      Map.pop.bit(a, V, lo, hi, pos, Map.bit(key, pos))\n\ndef Map.del.fin(a, -V: Kind(a), r: Map<a, V> & Maybe<a, V>) -> Map<a, V>:\n  (m2, x) = r\n  m2\n\ndef Map.del(a, -V: Kind(a), m: Map<a, V>, key: String) -> Map<a, V>:\n  Map.del.fin(a, V, Map.pop(a, V, m, key))\n\ndef Map.to_list.go(\n  a, -V: Kind(a), m: Map<a, V>, acc: List<a, Sigma<&2, a, String, _ => V>>\n) -> List<a, Sigma<&2, a, String, _ => V>>:\n  match m:\n    case MTip{}:\n      acc\n    case MLeaf{k, v}:\n      (k, v) <> acc\n    case MNode{pos, lo, hi}:\n      Map.to_list.go(a, V, lo, Map.to_list.go(a, V, hi, acc))\n\ndef Map.to_list(a, -V: Kind(a), m: Map<a, V>) ->\n  List<a, Sigma<&2, a, String, _ => V>>:\n  Map.to_list.go(a, V, m, Nil{})\n\ndef Map.keys.go(a, -V: Kind(a), m: Map<a, V>, acc: List<&2, String>) ->\n  List<&2, String>:\n  match m:\n    case MTip{}:\n      acc\n    case MLeaf{k, v}:\n      k <> acc\n    case MNode{pos, lo, hi}:\n      Map.keys.go(a, V, lo, Map.keys.go(a, V, hi, acc))\n\ndef Map.keys(a, -V: Kind(a), m: Map<a, V>) -> List<&2, String>:\n  Map.keys.go(a, V, m, Nil{})\n\ndef Map.from_list.go(\n  a, -V: Kind(a), kvs: List<a, Sigma<&2, a, String, _ => V>>, m: Map<a, V>\n) -> Map<a, V>:\n  match kvs:\n    case Nil{}:\n      m\n    case (k, v) <> t:\n      Map.from_list.go(a, V, t, Map.set(a, V, m, k, v))\n\ndef Map.from_list(a, -V: Kind(a), kvs: List<a, Sigma<&2, a, String, _ => V>>) ->\n  Map<a, V>:\n  Map.from_list.go(a, V, kvs, MTip{})\n\ndef Map.union(a, -V: Kind(a), m: Map<a, V>, n: Map<a, V>) -> Map<a, V>:\n  Map.from_list.go(a, V, Map.to_list(a, V, n), m)\n\ndef Map.size(a, -V: Kind(a), m: Map<a, V>) -> Nat:\n  match m:\n    case MTip{}:\n      0n\n    case MLeaf{k, v}:\n      1n\n    case MNode{pos, lo, hi}:\n      Nat.add(Map.size(a, V, lo), Map.size(a, V, hi))\n\ndef Map.values.go(a, -V: Kind(a), m: Map<a, V>, acc: List<a, V>) -> List<a, V>:\n  match m:\n    case MTip{}:\n      acc\n    case MLeaf{k, v}:\n      v <> acc\n    case MNode{pos, lo, hi}:\n      Map.values.go(a, V, lo, Map.values.go(a, V, hi, acc))\n\ndef Map.values(a, -V: Kind(a), m: Map<a, V>) -> List<a, V>:\n  Map.values.go(a, V, m, Nil{})\n",
    "stderr": "",
    "seconds": 0.03783587785437703
  },
  {
    "label": "open-claims",
    "command": [
      "/home/exedev/.hermes/profiles/mo-auditor/mo-research/bend-tools/node_modules/@oven/bun-linux-x64/bin/bun",
      "/home/exedev/.hermes/profiles/mo-auditor/workspace/bend-research/bend2/main.ts",
      "/tmp/bend-research-fe2vj0wm/sort/PROOF.bend"
    ],
    "exit": 1,
    "stdout": "",
    "stderr": "Error: 2 TODOs found.\nThe code is incomplete, and not a valid proof yet.\n",
    "seconds": 0.17111248918808997
  },
  {
    "label": "missing-laws-import",
    "command": [
      "/home/exedev/.hermes/profiles/mo-auditor/mo-research/bend-tools/node_modules/@oven/bun-linux-x64/bin/bun",
      "/home/exedev/.hermes/profiles/mo-auditor/workspace/bend-research/bend2/main.ts",
      "/tmp/bend-research-fe2vj0wm/sort/PROOF.bend"
    ],
    "exit": 1,
    "stdout": "",
    "stderr": "bend: PROOF.bend must import ./LAWS.bend (see bend --help)\n",
    "seconds": 0.10059709497727454
  },
  {
    "label": "false-equality",
    "command": [
      "/home/exedev/.hermes/profiles/mo-auditor/mo-research/bend-tools/node_modules/@oven/bun-linux-x64/bin/bun",
      "/home/exedev/.hermes/profiles/mo-auditor/workspace/bend-research/bend2/main.ts",
      "/tmp/bend-research-fe2vj0wm/false.bend"
    ],
    "exit": 1,
    "stdout": "",
    "stderr": "Error:\n- expected : '('\n- observed : ':'\nLocation:\n3 |   {0n == 1n : Nat}\n4>| def wrong:\n5 |   {==}\n",
    "seconds": 0.08756675920449197
  },
  {
    "label": "emit-js",
    "command": [
      "/home/exedev/.hermes/profiles/mo-auditor/mo-research/bend-tools/node_modules/@oven/bun-linux-x64/bin/bun",
      "/home/exedev/.hermes/profiles/mo-auditor/workspace/bend-research/bend2/main.ts",
      "demos/proof_insertion_sort/main.bend",
      "-o",
      "/tmp/bend-research-fe2vj0wm/sort.js"
    ],
    "exit": 0,
    "stdout": "",
    "stderr": "",
    "seconds": 0.20929465210065246
  },
  {
    "label": "run-js",
    "command": [
      "node",
      "/tmp/bend-research-fe2vj0wm/sort.js"
    ],
    "exit": 0,
    "stdout": "[1n, 2n, 3n]\n",
    "stderr": "",
    "seconds": 0.021506243851035833
  },
  {
    "label": "emit-c",
    "command": [
      "/home/exedev/.hermes/profiles/mo-auditor/mo-research/bend-tools/node_modules/@oven/bun-linux-x64/bin/bun",
      "/home/exedev/.hermes/profiles/mo-auditor/workspace/bend-research/bend2/main.ts",
      "demos/proof_insertion_sort/main.bend",
      "-o",
      "/tmp/bend-research-fe2vj0wm/sort.c"
    ],
    "exit": 0,
    "stdout": "",
    "stderr": "",
    "seconds": 0.21310517005622387
  },
  {
    "label": "compile-c-zig",
    "command": [
      "/home/exedev/.hermes/profiles/mo-auditor/workspace/audit-tools/zig-x86_64-linux-0.16.0/zig",
      "cc",
      "-O2",
      "/tmp/bend-research-fe2vj0wm/sort.c",
      "-lpthread",
      "-lm",
      "-o",
      "/tmp/bend-research-fe2vj0wm/sort-bin"
    ],
    "exit": 0,
    "stdout": "",
    "stderr": "",
    "seconds": 0.5706987110897899
  },
  {
    "label": "run-c",
    "command": [
      "/tmp/bend-research-fe2vj0wm/sort-bin",
      "--threads",
      "1"
    ],
    "exit": 0,
    "stdout": "[1n, 2n, 3n]\n",
    "stderr": "",
    "seconds": 0.0009229129645973444
  }
]
```

## Corrected output

```json
[
  {
    "label": "bun-version",
    "command": [
      "/home/exedev/.hermes/profiles/mo-auditor/mo-research/bend-tools/node_modules/@oven/bun-linux-x64/bin/bun",
      "--version"
    ],
    "exit": 0,
    "stdout": "1.4.2\n",
    "stderr": "",
    "seconds": 0.0013654720969498158
  },
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
    "seconds": 0.019216148182749748
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
    "seconds": 0.209721886087209
  },
  {
    "label": "sort-evaluate",
    "command": [
      "/home/exedev/.hermes/profiles/mo-auditor/mo-research/bend-tools/node_modules/@oven/bun-linux-x64/bin/bun",
      "/home/exedev/.hermes/profiles/mo-auditor/workspace/bend-research/bend2/main.ts",
      "demos/proof_insertion_sort/main.bend"
    ],
    "exit": 0,
    "stdout": "[1n, 2n, 3n]\n",
    "stderr": "",
    "seconds": 0.2417622220236808
  },
  {
    "label": "base-discovery",
    "command": [
      "/home/exedev/.hermes/profiles/mo-auditor/mo-research/bend-tools/node_modules/@oven/bun-linux-x64/bin/bun",
      "/home/exedev/.hermes/profiles/mo-auditor/workspace/bend-research/bend2/main.ts",
      "base",
      "Map"
    ],
    "exit": 0,
    "stdout": "type Map<a, -V: Kind(a)> is Kind(a):\n  MTip{}\n  MLeaf{key: String, val: V}\n  MNode{pos: Nat, lo: Map<a, V>, hi: Map<a, V>}\n\ndef Map.bit.u(x: U32, k: Nat) -> Bool:\n  U32.is_ne(U32.and(U32.shrn(x, k), 1), 0)\n\ndef Map.bit.chr(c: Char, off: Nat) -> Char & Bool:\n  match c off:\n    case Chr{x} 0n:\n      (Chr{x}, True{})\n    case Chr{+x} 1n+b:\n      (Chr{x}, Map.bit.u(x, Nat.sub(31n, b)))\n\ndef Map.bit.go.chr(t: String, r: Char & Bool) -> String & Bool:\n  (c2, b) = r\n  (SCon{c2, t}, b)\n\ndef Map.bit.go.rec(c: Char, r: String & Bool) -> String & Bool:\n  (t2, b) = r\n  (SCon{c, t2}, b)\n\ndef Map.bit.go(key: String, ci: Nat, off: Nat) -> String & Bool:\n  match key:\n    case SNil{}:\n      (SNil{}, False{})\n    case SCon{c, t}:\n      match ci:\n        case 0n:\n          Map.bit.go.chr(t, Map.bit.chr(c, off))\n        case 1n+j:\n          Map.bit.go.rec(c, Map.bit.go(t, j, off))\n\ndef Map.bit.at(key: String, co: Nat & Nat) -> String & Bool:\n  (ci, off) = co\n  Map.bit.go(key, ci, off)\n\ndef Map.bit(key: String, pos: Nat) -> String & Bool:\n  Map.bit.at(key, Nat.divmod(pos, 33n))\n\nlaw Map.msb.u:\n  for n: Nat\n  for +x: U32\n  Nat\n\ndef Map.msb.u.if(p: Nat, x2: U32, z: Bool) -> Nat:\n  match z:\n    case True{}:\n      0n\n    case False{}:\n      Nat.add(1n, Map.msb.u(p, U32.shr(x2)))\n\ndef Map.msb.u(n, x):\n  match n:\n    case 0n:\n      0n\n    case 1n+p:\n      Map.msb.u.if(p, x, U32.is_zero(x))\n\ndef Map.diff.chr(x: U32) -> Nat:\n  Nat.sub(33n, Map.msb.u(32n, x))\n\ndef Map.diff.step(x: Char, y: Char) -> Nat & Bool:\n  match x y:\n    case Chr{+cx} Chr{+cy}:\n      (Map.diff.chr(U32.xor(cx, cy)), U32.is_eq(cx, cy))\n\nlaw Map.diff:\n  for a: String\n  for b: String\n  Nat\n\ndef Map.diff.fin(xt: String, yt: String, rc: Nat & Bool) -> Nat:\n  (r, c) = rc\n  match c:\n    case True{}:\n      Nat.add(33n, Map.diff(xt, yt))\n    case False{}:\n      r\n\ndef Map.diff(a, b):\n  match a b:\n    case SNil{} SNil{}:\n      0n\n    case SNil{} SCon{h, t}:\n      0n\n    case SCon{h, t} SNil{}:\n      0n\n    case SCon{x, xt} SCon{y, yt}:\n      Map.diff.fin(xt, yt, Map.diff.step(x, y))\n\ndef Map.new(a, -V: Kind(a)) -> Map<a, V>:\n  MTip{}\n\nlaw Map.put:\n  for -a  : Quant\n  for -V  : Kind(a)\n  for m   : Map<a, V>\n  for key : String\n  for x   : V\n  Map<a, V>\n\ndef Map.put.bit(\n  a, -V: Kind(a), x: V, p2: Nat, lo: Map<a, V>, hi: Map<a, V>, kb: String & Bool\n) -> Map<a, V>:\n  (key2, b) = kb\n  match b:\n    case False{}:\n      MNode{p2, Map.put(a, V, lo, key2, x), hi}\n    case True{}:\n      MNode{p2, lo, Map.put(a, V, hi, key2, x)}\n\ndef Map.put(a, V, m, key, x):\n  match m:\n    case MTip{}:\n      MLeaf{key, x}\n    case MLeaf{k, v}:\n      MLeaf{k, x}\n    case MNode{+pos, lo, hi}:\n      Map.put.bit(a, V, x, pos, lo, hi, Map.bit(key, pos))\n\ndef Map.ins.splice.bit(\n  a, -V: Kind(a), x: V, rest: Map<a, V>, pb: Nat, kb: String & Bool\n) -> Map<a, V>:\n  (key2, b) = kb\n  match b:\n    case False{}:\n      MNode{pb, MLeaf{key2, x}, rest}\n    case True{}:\n      MNode{pb, rest, MLeaf{key2, x}}\n\ndef Map.ins.splice(\n  a, -V: Kind(a), +p: Nat, key: String, x: V, rest: Map<a, V>\n) -> Map<a, V>:\n  Map.ins.splice.bit(a, V, x, rest, p, Map.bit(key, p))\n\nlaw Map.ins:\n  for -a  : Quant\n  for -V  : Kind(a)\n  for m   : Map<a, V>\n  for key : String\n  for x   : V\n  for +p  : Nat\n  Map<a, V>\n\ndef Map.ins.deep(\n  a, -V: Kind(a), x: V, lo: Map<a, V>, hi: Map<a, V>, pb: Nat, qb: Nat,\n  kb: String & Bool\n) -> Map<a, V>:\n  (key2, b) = kb\n  match b:\n    case False{}:\n      MNode{qb, Map.ins(a, V, lo, key2, x, pb), hi}\n    case True{}:\n      MNode{qb, lo, Map.ins(a, V, hi, key2, x, pb)}\n\ndef Map.ins.if(\n  a, -V: Kind(a), key: String, x: V, lo: Map<a, V>, hi: Map<a, V>, +p2: Nat,\n  pb: Nat, t: Bool\n) -> Map<a, V>:\n  match t:\n    case False{}:\n      Map.ins.splice(a, V, pb, key, x, MNode{p2, lo, hi})\n    case True{}:\n      Map.ins.deep(a, V, x, lo, hi, pb, p2, Map.bit(key, p2))\n\ndef Map.ins(a, V, m, key, x, p):\n  match m:\n    case MTip{}:\n      MLeaf{key, x}\n    case MLeaf{k, v}:\n      Map.ins.splice(a, V, p, key, x, MLeaf{k, v})\n    case MNode{+pos, lo, hi}:\n      Map.ins.if(a, V, key, x, lo, hi, pos, p, Nat.is_lt(pos, p))\n\ndef Map.lo(\n  a, -V: Kind(a), -R: Type, p2: Nat, hi: Map<a, V>, r0: Map<a, V> & R\n) -> Map<a, V> & R:\n  (lo2, r) = r0\n  (MNode{p2, lo2, hi}, r)\n\ndef Map.hi(\n  a, -V: Kind(a), -R: Type, p2: Nat, lo: Map<a, V>, r0: Map<a, V> & R\n) -> Map<a, V> & R:\n  (hi2, r) = r0\n  (MNode{p2, lo, hi2}, r)\n\nlaw Map.seek:\n  for -a  : Quant\n  for -V  : Kind(a)\n  for m   : Map<a, V>\n  for key : String\n  Map<a, V> & String & Maybe<&2, String>\n\ndef Map.seek.bit(\n  a, -V: Kind(a), lo: Map<a, V>, hi: Map<a, V>, p2: Nat, kb: String & Bool\n) -> Map<a, V> & String & Maybe<&2, String>:\n  (key2, b) = kb\n  match b:\n    case False{}:\n      Map.lo(a, V, String & Maybe<&2, String>, p2, hi, Map.seek(a, V, lo, key2))\n    case True{}:\n      Map.hi(a, V, String & Maybe<&2, String>, p2, lo, Map.seek(a, V, hi, key2))\n\ndef Map.seek(a, V, m, key):\n  match m:\n    case MTip{}:\n      (MTip{}, key, None{})\n    case MLeaf{+k, v}:\n      (MLeaf{k, v}, key, Some{k})\n    case MNode{+pos, lo, hi}:\n      Map.seek.bit(a, V, lo, hi, pos, Map.bit(key, pos))\n\ndef Map.set.fin.go(\n  a, -V: Kind(a), m: Map<a, V>, key: String, x: V, r: (String & String) & Cmp\n) -> Map<a, V>:\n  ((keyb2, k2), c) = r\n  match c:\n    case LT{}:\n      Map.ins(a, V, m, key, x, Map.diff(keyb2, k2))\n    case EQ{}:\n      Map.put(a, V, m, key, x)\n    case GT{}:\n      Map.ins(a, V, m, key, x, Map.diff(keyb2, k2))\n\ndef Map.set.fin(\n  a, -V: Kind(a), m: Map<a, V>, key: String, x: V, keyb: String, k: String\n) -> Map<a, V>:\n  Map.set.fin.go(a, V, m, key, x, String.cmp(keyb, k))\n\ndef Map.set.go(\n  a, -V: Kind(a), x: V, r: Map<a, V> & String & Maybe<&2, String>\n) -> Map<a, V>:\n  (m2, key2, found) = r\n  match found:\n    case None{}:\n      MLeaf{key2, x}\n    case Some{k}:\n      +ka = {key2 : String}\n      Map.set.fin(a, V, m2, ka, x, ka, k)\n\ndef Map.set(a, -V: Kind(a), m: Map<a, V>, key: String, x: V) -> Map<a, V>:\n  Map.set.go(a, V, x, Map.seek(a, V, m, key))\n\ndef Map.has.leaf(a, -V: Kind(a), v: V, r: (String & String) & Cmp) ->\n  Map<a, V> & Bool:\n  ((key2, k2), c) = r\n  (MLeaf{k2, v}, Cmp.is_eq(c))\n\nlaw Map.has:\n  for -a  : Quant\n  for -V  : Kind(a)\n  for m   : Map<a, V>\n  for key : String\n  Map<a, V> & Bool\n\ndef Map.has.bit(\n  a, -V: Kind(a), lo: Map<a, V>, hi: Map<a, V>, p2: Nat, kb: String & Bool\n) -> Map<a, V> & Bool:\n  (key2, b) = kb\n  match b:\n    case False{}:\n      Map.lo(a, V, Bool, p2, hi, Map.has(a, V, lo, key2))\n    case True{}:\n      Map.hi(a, V, Bool, p2, lo, Map.has(a, V, hi, key2))\n\ndef Map.has(a, V, m, key):\n  match m:\n    case MTip{}:\n      (MTip{}, False{})\n    case MLeaf{k, v}:\n      Map.has.leaf(a, V, v, String.cmp(key, k))\n    case MNode{+pos, lo, hi}:\n      Map.has.bit(a, V, lo, hi, pos, Map.bit(key, pos))\n\ndef Map.get.leaf(-V: Data, d: V, +v: V, r: (String & String) & Cmp) ->\n  Map<&2, V> & V:\n  ((key2, k2), c) = r\n  match c:\n    case LT{}:\n      (MLeaf{k2, v}, d)\n    case EQ{}:\n      (MLeaf{k2, v}, v)\n    case GT{}:\n      (MLeaf{k2, v}, d)\n\nlaw Map.get:\n  for -V  : Data\n  for d   : V\n  for m   : Map<&2, V>\n  for key : String\n  Map<&2, V> & V\n\ndef Map.get.bit(\n  -V: Data, d: V, lo: Map<&2, V>, hi: Map<&2, V>, p2: Nat, kb: String & Bool\n) -> Map<&2, V> & V:\n  (key2, b) = kb\n  match b:\n    case False{}:\n      Map.lo(&2, V, V, p2, hi, Map.get(V, d, lo, key2))\n    case True{}:\n      Map.hi(&2, V, V, p2, lo, Map.get(V, d, hi, key2))\n\ndef Map.get(V, d, m, key):\n  match m:\n    case MTip{}:\n      (MTip{}, d)\n    case MLeaf{k, v}:\n      Map.get.leaf(V, d, v, String.cmp(key, k))\n    case MNode{+pos, lo, hi}:\n      Map.get.bit(V, d, lo, hi, pos, Map.bit(key, pos))\n\ndef Map.pop.lo(\n  a, -V: Kind(a), pos: Nat, hi: Map<a, V>, r0: Map<a, V> & Maybe<a, V>\n) -> Map<a, V> & Maybe<a, V>:\n  (lo, r) = r0\n  match lo:\n    case MTip{}:\n      (hi, r)\n    case lo2:\n      (MNode{pos, lo2, hi}, r)\n\ndef Map.pop.hi(\n  a, -V: Kind(a), pos: Nat, lo: Map<a, V>, r0: Map<a, V> & Maybe<a, V>\n) -> Map<a, V> & Maybe<a, V>:\n  (hi, r) = r0\n  match hi:\n    case MTip{}:\n      (lo, r)\n    case hi2:\n      (MNode{pos, lo, hi2}, r)\n\ndef Map.pop.leaf(a, -V: Kind(a), v: V, r: (String & String) & Cmp) ->\n  Map<a, V> & Maybe<a, V>:\n  ((key2, k2), c) = r\n  match c:\n    case LT{}:\n      (MLeaf{k2, v}, None{})\n    case EQ{}:\n      (MTip{}, Some{v})\n    case GT{}:\n      (MLeaf{k2, v}, None{})\n\nlaw Map.pop:\n  for -a  : Quant\n  for -V  : Kind(a)\n  for m   : Map<a, V>\n  for key : String\n  Map<a, V> & Maybe<a, V>\n\ndef Map.pop.bit(\n  a, -V: Kind(a), lo: Map<a, V>, hi: Map<a, V>, p2: Nat, kb: String & Bool\n) -> Map<a, V> & Maybe<a, V>:\n  (key2, b) = kb\n  match b:\n    case False{}:\n      Map.pop.lo(a, V, p2, hi, Map.pop(a, V, lo, key2))\n    case True{}:\n      Map.pop.hi(a, V, p2, lo, Map.pop(a, V, hi, key2))\n\ndef Map.pop(a, V, m, key):\n  match m:\n    case MTip{}:\n      (MTip{}, None{})\n    case MLeaf{k, v}:\n      Map.pop.leaf(a, V, v, String.cmp(key, k))\n    case MNode{+pos, lo, hi}:\n      Map.pop.bit(a, V, lo, hi, pos, Map.bit(key, pos))\n\ndef Map.del.fin(a, -V: Kind(a), r: Map<a, V> & Maybe<a, V>) -> Map<a, V>:\n  (m2, x) = r\n  m2\n\ndef Map.del(a, -V: Kind(a), m: Map<a, V>, key: String) -> Map<a, V>:\n  Map.del.fin(a, V, Map.pop(a, V, m, key))\n\ndef Map.to_list.go(\n  a, -V: Kind(a), m: Map<a, V>, acc: List<a, Sigma<&2, a, String, _ => V>>\n) -> List<a, Sigma<&2, a, String, _ => V>>:\n  match m:\n    case MTip{}:\n      acc\n    case MLeaf{k, v}:\n      (k, v) <> acc\n    case MNode{pos, lo, hi}:\n      Map.to_list.go(a, V, lo, Map.to_list.go(a, V, hi, acc))\n\ndef Map.to_list(a, -V: Kind(a), m: Map<a, V>) ->\n  List<a, Sigma<&2, a, String, _ => V>>:\n  Map.to_list.go(a, V, m, Nil{})\n\ndef Map.keys.go(a, -V: Kind(a), m: Map<a, V>, acc: List<&2, String>) ->\n  List<&2, String>:\n  match m:\n    case MTip{}:\n      acc\n    case MLeaf{k, v}:\n      k <> acc\n    case MNode{pos, lo, hi}:\n      Map.keys.go(a, V, lo, Map.keys.go(a, V, hi, acc))\n\ndef Map.keys(a, -V: Kind(a), m: Map<a, V>) -> List<&2, String>:\n  Map.keys.go(a, V, m, Nil{})\n\ndef Map.from_list.go(\n  a, -V: Kind(a), kvs: List<a, Sigma<&2, a, String, _ => V>>, m: Map<a, V>\n) -> Map<a, V>:\n  match kvs:\n    case Nil{}:\n      m\n    case (k, v) <> t:\n      Map.from_list.go(a, V, t, Map.set(a, V, m, k, v))\n\ndef Map.from_list(a, -V: Kind(a), kvs: List<a, Sigma<&2, a, String, _ => V>>) ->\n  Map<a, V>:\n  Map.from_list.go(a, V, kvs, MTip{})\n\ndef Map.union(a, -V: Kind(a), m: Map<a, V>, n: Map<a, V>) -> Map<a, V>:\n  Map.from_list.go(a, V, Map.to_list(a, V, n), m)\n\ndef Map.size(a, -V: Kind(a), m: Map<a, V>) -> Nat:\n  match m:\n    case MTip{}:\n      0n\n    case MLeaf{k, v}:\n      1n\n    case MNode{pos, lo, hi}:\n      Nat.add(Map.size(a, V, lo), Map.size(a, V, hi))\n\ndef Map.values.go(a, -V: Kind(a), m: Map<a, V>, acc: List<a, V>) -> List<a, V>:\n  match m:\n    case MTip{}:\n      acc\n    case MLeaf{k, v}:\n      v <> acc\n    case MNode{pos, lo, hi}:\n      Map.values.go(a, V, lo, Map.values.go(a, V, hi, acc))\n\ndef Map.values(a, -V: Kind(a), m: Map<a, V>) -> List<a, V>:\n  Map.values.go(a, V, m, Nil{})\n",
    "stderr": "",
    "seconds": 0.020813032053411007
  },
  {
    "label": "open-claims",
    "command": [
      "/home/exedev/.hermes/profiles/mo-auditor/mo-research/bend-tools/node_modules/@oven/bun-linux-x64/bin/bun",
      "/home/exedev/.hermes/profiles/mo-auditor/workspace/bend-research/bend2/main.ts",
      "/tmp/bend-research-_1fhkt9g/sort/PROOF.bend"
    ],
    "exit": 1,
    "stdout": "",
    "stderr": "Error: 2 TODOs found.\nThe code is incomplete, and not a valid proof yet.\n",
    "seconds": 0.23251258092932403
  },
  {
    "label": "missing-laws-import",
    "command": [
      "/home/exedev/.hermes/profiles/mo-auditor/mo-research/bend-tools/node_modules/@oven/bun-linux-x64/bin/bun",
      "/home/exedev/.hermes/profiles/mo-auditor/workspace/bend-research/bend2/main.ts",
      "/tmp/bend-research-_1fhkt9g/sort/PROOF.bend"
    ],
    "exit": 1,
    "stdout": "",
    "stderr": "bend: PROOF.bend must import ./LAWS.bend (see bend --help)\n",
    "seconds": 0.07987925386987627
  },
  {
    "label": "false-equality",
    "command": [
      "/home/exedev/.hermes/profiles/mo-auditor/mo-research/bend-tools/node_modules/@oven/bun-linux-x64/bin/bun",
      "/home/exedev/.hermes/profiles/mo-auditor/workspace/bend-research/bend2/main.ts",
      "/tmp/bend-research-_1fhkt9g/false.bend"
    ],
    "exit": 1,
    "stdout": "",
    "stderr": "Error:\n- expected : 0n\n- observed : 1n\nLocation: wrong\n4 | def wrong():\n5>|   {==}\n6 | \n",
    "seconds": 0.1710373170208186
  },
  {
    "label": "emit-js",
    "command": [
      "/home/exedev/.hermes/profiles/mo-auditor/mo-research/bend-tools/node_modules/@oven/bun-linux-x64/bin/bun",
      "/home/exedev/.hermes/profiles/mo-auditor/workspace/bend-research/bend2/main.ts",
      "demos/proof_insertion_sort/main.bend",
      "-o",
      "/tmp/bend-research-_1fhkt9g/sort.js"
    ],
    "exit": 0,
    "stdout": "",
    "stderr": "",
    "seconds": 0.2678669060114771
  },
  {
    "label": "run-js",
    "command": [
      "node",
      "/tmp/bend-research-_1fhkt9g/sort.js"
    ],
    "exit": 0,
    "stdout": "[1n, 2n, 3n]\n",
    "stderr": "",
    "seconds": 0.02460149792023003
  },
  {
    "label": "emit-c",
    "command": [
      "/home/exedev/.hermes/profiles/mo-auditor/mo-research/bend-tools/node_modules/@oven/bun-linux-x64/bin/bun",
      "/home/exedev/.hermes/profiles/mo-auditor/workspace/bend-research/bend2/main.ts",
      "demos/proof_insertion_sort/main.bend",
      "-o",
      "/tmp/bend-research-_1fhkt9g/sort.c"
    ],
    "exit": 0,
    "stdout": "",
    "stderr": "",
    "seconds": 0.21781460591591895
  },
  {
    "label": "compile-c-zig",
    "command": [
      "/home/exedev/.hermes/profiles/mo-auditor/workspace/audit-tools/zig-x86_64-linux-0.16.0/zig",
      "cc",
      "-O2",
      "/tmp/bend-research-_1fhkt9g/sort.c",
      "-lpthread",
      "-lm",
      "-o",
      "/tmp/bend-research-_1fhkt9g/sort-bin"
    ],
    "exit": 0,
    "stdout": "",
    "stderr": "",
    "seconds": 0.4437574530020356
  },
  {
    "label": "run-c",
    "command": [
      "/tmp/bend-research-_1fhkt9g/sort-bin",
      "--threads",
      "1"
    ],
    "exit": 0,
    "stdout": "[1n, 2n, 3n]\n",
    "stderr": "",
    "seconds": 0.0008483221754431725
  }
]
```
