#!/bin/bash
# usage: verify-program.sh <worktree> <prog>   tests on every module, then every `# run:` line against its .expected
W=$1; P=$2; D=$W/examples/programs/$P; MO=$W/toolchain/zig-out/bin/mo
export PATH=$HOME/.local/share/mise/installs/zig/0.16.0/bin:$PATH
cd $D || exit 1
pass=0; fail=0
for f in *.mo; do
  out=$(timeout 300 $MO test $f 2>&1 | grep -E 'passed|failed' | tail -1); echo "$f: $out"
  echo "$out" | grep -q ' 0 failed' && pass=$((pass+1)) || fail=$((fail+1))
done
n=0; expect_exit=0
python3 - "$D" "$P" > /tmp/runs-$P-$$.txt <<'PY'
import sys,re
d,p=sys.argv[1],sys.argv[2]
lines=open(f"{d}/main.mo").read().split("\n")
runs=[]; 
for l in lines:
    if l.startswith("# run:"): runs.append([l[6:].strip(), 0])
    elif l.startswith("# exit:") and runs: runs[-1][1]=int(l[7:].strip())
    elif not l.startswith("#"): break
for i,(args,code) in enumerate(runs):
    exp = f"{p}.expected" if i==0 else f"{p}-{i+1}.expected"
    print(f"{code}\t{exp}\t{args}")
PY
while IFS=$'\t' read -r code exp args; do
  n=$((n+1)); actual=$(timeout 120 $MO run main.mo -- $args 2>/dev/null); rc=$?
  if [ "$actual" == "$(cat $exp 2>/dev/null)" ] && [ "$rc" == "$code" ]; then echo "run $n ok ($args)"; pass=$((pass+1)); else echo "run $n DIFFERS (exit $rc, wanted $code) ($args)"; fail=$((fail+1)); fi
done < /tmp/runs-$P-$$.txt
echo "SUMMARY $P: $pass ok, $fail failed"
