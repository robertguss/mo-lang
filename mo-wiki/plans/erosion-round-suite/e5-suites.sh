#!/bin/bash
# usage: e5-suites.sh <lang: go|python|elixir|mo|morun>   generation five's suites for one program, one after another
# (never two at once on the Mac: the suites' drains and the pkill of servers under the temp folder). Results in results/e5-<lang>-*.txt,
# one summary line per suite in results/e5-suites.out.
L=$1; R=/Users/robertguss/Projects/startups; M=$R/mo-lang; SU=$M/mo-wiki/plans; OUT=$SU/erosion-round-suite/results; S=${SCRATCH:-/tmp}
W=$R/mo-lang-erosion5-$L; [ $L = morun ] && W=$R/mo-lang-erosion5-mo
case $L in
  go)   (cd $W/experiments/control-run/go/jobq && go build -o $S/jobq-e5-go . ) && (cd $R/mo-lang-control7-go/experiments/control-run/go/jobq && go build -o $S/jobq-r7-go .)
        B=$S/jobq-e5-go; SERVE="$B serve {dir} --port {port}"; VERIFY="$B verify {dir}"; COMPACT="$B compact {dir}"; CWD=$W; OLD="$S/jobq-r7-go serve {dir} --port {port}"; OLDCWD=$R/mo-lang-control7-go;;
  python) CWD=$W/experiments/control-run/python/jobq; (cd $CWD && uv sync -q); SERVE="uv run jobq serve {dir} --port {port}"; VERIFY="uv run jobq verify {dir}"; COMPACT="uv run jobq compact {dir}"
        OLDCWD=$R/mo-lang-control7-python/experiments/control-run/python/jobq; (cd $OLDCWD && uv sync -q); OLD="uv run jobq serve {dir} --port {port}";;
  elixir) cd $W && eval "$(mise env)"; CWD=$W/experiments/control-run/elixir/jobq; (cd $CWD && mix deps.get >/dev/null 2>&1; mix escript.build 2>&1 | tail -1)
        SERVE="$CWD/jobq serve {dir} --port {port}"; VERIFY="$CWD/jobq verify {dir}"; COMPACT="$CWD/jobq compact {dir}"; OLDCWD=$R/mo-lang-control10-elixir/experiments/control-run/elixir/jobq; OLD="$OLDCWD/jobq serve {dir} --port {port}";;
  mo)   MO=$W/toolchain/zig-out/bin/mo; (cd $S && timeout 300 $MO build $W/examples/programs/jobq/main.mo -o jobq-e5 >/dev/null) ; B=$S/zig-out/mo-build/jobq-e5/jobq-e5
        SERVE="$B serve {dir} --port {port}"; VERIFY="$B verify {dir}"; COMPACT="$B compact {dir}"; CWD=$W
        (cd $S && timeout 300 $R/mo-lang-control7-mo/toolchain/zig-out/bin/mo build $R/mo-lang-control7-mo/examples/programs/jobq/main.mo -o jobq-r7 >/dev/null); OLD="$S/zig-out/mo-build/jobq-r7/jobq-r7 serve {dir} --port {port}"; OLDCWD=$R/mo-lang-control7-mo;;
  morun) MO=$W/toolchain/zig-out/bin/mo; P=$W/examples/programs/jobq/main.mo
        SERVE="$MO run $P -- serve {dir} --port {port}"; VERIFY="$MO run $P -- verify {dir}"; COMPACT="$MO run $P -- compact {dir}"; CWD=$W
        OLD="$S/zig-out/mo-build/jobq-r7/jobq-r7 serve {dir} --port {port}"; OLDCWD=$R/mo-lang-control7-mo;;
esac
export MO_CORES=1
drain() { for i in $(seq 1 60); do n=$(netstat -an | grep -c TIME_WAIT); [ "$n" -lt 1500 ] && return; sleep 3; done; }
suite() { # name cmd...
  name=$1; shift; echo "## $L $name $(date '+%H:%M:%S')" >> $OUT/e5-suites.out
  timeout 1500 "$@" > $OUT/e5-$L-$name.txt 2>&1; grep -E 'passed, [0-9]+ defects|^FAIL' $OUT/e5-$L-$name.txt | tail -12 >> $OUT/e5-suites.out
  pkill -f 'serve /var/folders' 2>/dev/null; drain
}
suite regressions python3 -u $SU/control-run-8-suite/regressions.py --serve "$SERVE" --cwd $CWD
suite defects1 python3 -u $SU/control-run-8-suite/defects.py --serve "$SERVE" --cwd $CWD --old-serve "$OLD" --old-cwd $OLDCWD --compact "$COMPACT"
suite defects2 python3 -u $SU/erosion-round-suite/defects2.py --serve "$SERVE" --verify "$VERIFY" --compact "$COMPACT" --cwd $CWD
suite defects3 python3 -u $SU/erosion-round-suite/defects3.py --serve "$SERVE" --verify "$VERIFY" --cwd $CWD
suite defects4 python3 -u $SU/erosion-round-suite/defects4.py --serve "$SERVE" --verify "$VERIFY" --compact "$COMPACT" --cwd $CWD
suite defects5 python3 -u $SU/erosion-round-suite/defects5.py --serve "$SERVE" --verify "$VERIFY" --compact "$COMPACT" --cwd $CWD
echo "## $L done $(date '+%H:%M:%S')" >> $OUT/e5-suites.out
