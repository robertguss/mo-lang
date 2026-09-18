#!/bin/bash
# The eight cells (gen3, gen4, cheap, none) x (contracts on, MO_CONTRACTS=0), trial 1 of all eight, then trial 2.
# One run at a time; each log opens with the date, uptime and the top of ps; 30,000 jobs, MO_CORES=1.
S=/tmp/claude-1000/-home-exedev-Projects-mo-lang/b2557fa4-9d5d-4e16-b574-25ec6f9b23b8/scratchpad/g4c
wt() { case $1 in gen3) echo /home/exedev/Projects/mo-lang-erosion3-mo;; gen4) echo /home/exedev/Projects/mo-lang-erosion4-mo;; *) echo /home/exedev/Projects/mo-lang-erosion4-control;; esac; }
python3 $S/watchdog.py 2>>$S/logs/watchdog.log & WD=$!
for trial in ${TRIALS:-1 2}; do
  for v in gen3 gen4 cheap none; do
    for c in on off; do
      L=$S/logs/$v-contracts-$c-trial$trial.log; W=$(wt $v)
      {
        echo "# $v, contracts $c, trial $trial, 30000 jobs, MO_CORES=1, binary $S/bin/$v/jobq, cwd $W"
        echo "# date: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
        echo "# uptime: $(uptime)"
        echo "# top of ps:"; ps aux --sort=-%cpu | head -6 | sed 's/^/#   /'
        if [ $c = off ]; then CE="MO_CONTRACTS=0"; else CE=""; fi
        cd $W
        env $CE TRIES_FIELD=max_tries MO_CORES=1 timeout 300 python3 -u $S/measure.py --serve "timeout 240 $S/bin/$v/jobq serve {dir} --port {port}" --cwd $W --jobs 30000 2>&1
        echo "# exit: $?"
        echo "# jobq left: $(pgrep -x jobq | python3 -c 'import sys; print(sys.stdin.read().split() or "none")')"
      } > $L 2>&1
      pkill -x jobq 2>/dev/null
      echo "== $L"; grep -E "creates|32 workers|after pairs|restart" $L
      sleep 3
    done
  done
done
kill $WD
echo RUN-DONE
