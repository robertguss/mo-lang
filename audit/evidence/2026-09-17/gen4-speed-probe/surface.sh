#!/bin/bash
S=/tmp/claude-1000/-home-exedev-Projects-mo-lang/aca79dff-6e6e-4946-9645-b1abe7522f67/scratchpad/gen4probe
for g in 3 4; do
  WT=/home/exedev/Projects/mo-lang-erosion$g-mo; SP=$((18700+g))
  echo "== surface run gen $g, MO_CORES=1, ${JOBS:-30000} jobs, surface on $SP"
  cd $WT
  TRIES_FIELD=max_tries MO_CORES=1 python3 -u $S/measure.py --serve "MO_SURFACE=$SP $WT/zig-out/mo-build/jobq-surface/jobq-surface serve {dir} --port {port}" --cwd $WT --jobs ${JOBS:-30000} > $S/surface$g.measure 2>&1 &
  M=$!
  : > $S/surface$g.slowest
  while kill -0 $M 2>/dev/null; do
    sleep 4
    echo "--- $(date -u +%T)" >> $S/surface$g.slowest
    python3 -c "
import urllib.request
for p in ['/slowest?n=10','/memory']:
    try: print(urllib.request.urlopen('http://127.0.0.1:$SP'+p, timeout=2).read().decode())
    except Exception as e: print('ERR', e)" >> $S/surface$g.slowest 2>&1
  done
  tail -12 $S/surface$g.measure
  pkill -f "jobq-surface serve" 2>/dev/null
done
echo SURFACE-DONE
