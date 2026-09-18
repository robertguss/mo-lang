#!/bin/bash
# generation six's speed rows on Robert's Mac, by the lead, one server at a time: change 3 and change 6 of each program,
# alternating (3, 6, 3, 6), control-run-8-suite/measure.py at 30,000 jobs, MO_CORES=1. The Mo programs are built with the
# same `mo` (main's, in erosion6-mo) so the row compares programs and not toolchains. Output: results/e6-speed.txt
R=/Users/robertguss/Projects/startups; M=$R/mo-lang; SU=$M/mo-wiki/plans; OUT=$SU/erosion-round-suite/results/e6-speed.txt; S=/tmp/e6-speed; mkdir -p $S
G="python3 $M/toolchain/bench/step36/guard.py 900 --"; export MO_CORES=1
say() { echo "$@" | tee -a $OUT; }
say "# $(date '+%Y-%m-%d %H:%M:%S %Z') $(uptime | sed 's/.*load/load/')"; say "# top by cpu: $(ps -axo pcpu=,comm= | sort -rn | head -4 | python3 -c "import sys; print('; '.join(' '.join(l.split()[:2])[-60:] for l in sys.stdin))")"
MO=$R/mo-lang-erosion6-mo/toolchain/zig-out/bin/mo
for g in 3 6; do
  (cd $S && $G $MO build $R/mo-lang-erosion$g-mo/examples/programs/jobq/main.mo -o jobq-mo$g > $S/build-mo$g.txt 2>&1); say "build mo$g exit=$?"
  (cd $R/mo-lang-erosion$g-go/experiments/control-run/go/jobq && go build -o $S/jobq-go$g .); say "build go$g exit=$?"
  (cd $R/mo-lang-erosion$g-python/experiments/control-run/python/jobq && uv sync -q); say "build python$g exit=$?"
  (cd $R/mo-lang-erosion$g-elixir && eval "$(mise env)" && cd experiments/control-run/elixir/jobq && mix deps.get >/dev/null 2>&1 && mix escript.build >/dev/null 2>&1); say "build elixir$g exit=$?"
done
run() { # label cwd serve
  say "== $1 $(date '+%H:%M:%S') load $(sysctl -n vm.loadavg)"
  (cd $2 && timeout 1200 python3 -u $SU/control-run-8-suite/measure.py --serve "$3" --cwd $2 --jobs 30000) 2>&1 | tee -a $OUT; say "exit=${PIPESTATUS[0]}"
  pkill -f 'serve /var/folders' 2>/dev/null; pkill -f 'serve /private/var' 2>/dev/null
  for i in $(seq 1 40); do n=$(netstat -an | grep -c TIME_WAIT); [ "$n" -lt 1500 ] && break; sleep 3; done
}
for round in 1 2; do for g in 3 6; do
  run "mo change $g, binary, round $round" $S "$S/zig-out/mo-build/jobq-mo$g/jobq-mo$g serve {dir} --port {port}"
  run "python change $g, round $round" $R/mo-lang-erosion$g-python/experiments/control-run/python/jobq "uv run jobq serve {dir} --port {port}"
  (cd $R/mo-lang-erosion$g-elixir && eval "$(mise env)" && run "elixir change $g, round $round" $R/mo-lang-erosion$g-elixir/experiments/control-run/elixir/jobq "$R/mo-lang-erosion$g-elixir/experiments/control-run/elixir/jobq/jobq serve {dir} --port {port}")
done; done
for g in 3 6; do run "go change $g, one round (one full flush a write: about 150 s of creates)" $S "$S/jobq-go$g serve {dir} --port {port}"; done
say "# done $(date '+%H:%M:%S')"
