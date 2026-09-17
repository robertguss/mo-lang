#!/bin/bash
S=/tmp/claude-1000/-home-exedev-Projects-mo-lang/aca79dff-6e6e-4946-9645-b1abe7522f67/scratchpad/gen4probe
for g in 3 4; do
  WT=/home/exedev/Projects/mo-lang-erosion$g-mo
  F=max_tries; [ $g = 3 ] && F=max_tries
  echo "== gen $g, field $F, MO_CORES=1, ${JOBS:-30000} jobs"
  cd $WT
  TRIES_FIELD=$F MO_CORES=1 /usr/lib/linux-tools-6.8.0-139/perf record -F 499 -g -o $S/perf$g.data -- python3 -u $S/measure.py --serve "$WT/zig-out/mo-build/jobq/jobq serve {dir} --port {port}" --cwd $WT --jobs ${JOBS:-30000} 2>&1 | grep -v "^\[ perf" | tail -12
  pkill -f "jobq serve" 2>/dev/null
  echo "-- hot symbols in the server, gen $g"
  /usr/lib/linux-tools-6.8.0-139/perf report -i $S/perf$g.data --comm jobq --no-children --stdio --percent-limit 1.5 2>/dev/null | grep -v "^#" | grep -v "^$" | head -40
done

WT=/home/exedev/Projects/mo-lang-erosion4-mo; cd $WT
echo "== gen 4 again with MO_CONTRACTS=0 (the contracts off at run time), ${JOBS:-30000} jobs"
TRIES_FIELD=max_tries MO_CORES=1 MO_CONTRACTS=0 python3 -u $S/measure.py --serve "$WT/zig-out/mo-build/jobq/jobq serve {dir} --port {port}" --cwd $WT --jobs ${JOBS:-30000} 2>&1 | tail -8
pkill -f "jobq serve" 2>/dev/null
echo "== gen 3 again with MO_CONTRACTS=0"
WT=/home/exedev/Projects/mo-lang-erosion3-mo; cd $WT
TRIES_FIELD=max_tries MO_CORES=1 MO_CONTRACTS=0 python3 -u $S/measure.py --serve "$WT/zig-out/mo-build/jobq/jobq serve {dir} --port {port}" --cwd $WT --jobs ${JOBS:-30000} 2>&1 | tail -8
pkill -f "jobq serve" 2>/dev/null
echo PROBE2-DONE
