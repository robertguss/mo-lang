#!/bin/bash
# Part C: one perf record of the cheap variant (contracts on), then the /slowest surface run of it, as the speed probe did.
S=/tmp/claude-1000/-home-exedev-Projects-mo-lang/b2557fa4-9d5d-4e16-b574-25ec6f9b23b8/scratchpad/g4c
W=/home/exedev/Projects/mo-lang-erosion4-control; PERF=/usr/lib/linux-tools-6.8.0-139/perf
python3 $S/watchdog.py 2>>$S/logs/watchdog.log & WD=$!
head() { echo "# date: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"; echo "# uptime: $(uptime)"; echo "# top of ps:"; ps aux --sort=-%cpu | command head -6 | sed 's/^/#   /'; }
cd $W
{
  echo "# perf of the cheap variant, contracts on, 30000 jobs, MO_CORES=1"; head
  TRIES_FIELD=max_tries MO_CORES=1 timeout 300 $PERF record -F 499 -g -o $S/perf-cheap.data -- python3 -u $S/measure.py --serve "timeout --foreground 240 $S/bin/cheap/jobq serve {dir} --port {port}" --cwd $W --jobs 30000 2>&1 | grep -v "^\[ perf"
  pkill -x jobq 2>/dev/null
  echo "-- hot symbols in the server, cheap"
  $PERF report -i $S/perf-cheap.data --comm jobq --no-children --stdio --percent-limit 1.5 2>/dev/null | grep -v "^#" | grep -v "^$" | command head -60
  echo "-- flat, top 15"
  $PERF report -i $S/perf-cheap.data --comm jobq --no-children --stdio -g none --percent-limit 0.5 2>/dev/null | grep -v "^#" | grep -v "^$" | command head -15
} > $S/logs/perf-cheap.log 2>&1
sleep 3
SP=18710
{
  echo "# surface run of the cheap variant, contracts on, 30000 jobs, MO_CORES=1, surface on $SP"; head
} > $S/logs/surface-cheap.measure
cp $S/logs/surface-cheap.measure $S/logs/surface-cheap.slowest
TRIES_FIELD=max_tries MO_CORES=1 timeout 300 python3 -u $S/measure.py --serve "MO_SURFACE=$SP timeout --foreground 240 $S/bin/cheap/jobq-surface serve {dir} --port {port}" --cwd $W --jobs 30000 >> $S/logs/surface-cheap.measure 2>&1 &
M=$!
while kill -0 $M 2>/dev/null; do
  sleep 4
  echo "--- $(date -u +%T)" >> $S/logs/surface-cheap.slowest
  python3 -c "
import urllib.request
for p in ['/slowest?n=10','/memory']:
    try: print(urllib.request.urlopen('http://127.0.0.1:$SP'+p, timeout=2).read().decode())
    except Exception as e: print('ERR', e)" >> $S/logs/surface-cheap.slowest 2>&1
done
pkill -x jobq-surface 2>/dev/null
kill $WD
echo "# jobq left: $(pgrep -x jobq) $(pgrep -x jobq-surface)" >> $S/logs/surface-cheap.measure
echo PARTC-DONE
