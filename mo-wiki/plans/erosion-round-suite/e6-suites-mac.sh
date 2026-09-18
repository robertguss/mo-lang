#!/bin/bash
# usage: e6-suites-mac.sh <lang: go|python|elixir|mo|morun>   generation six's suites for one program, one after another, on Robert's Mac.
# Rewritten 18 Sep 2026 after the auditor's reading (G6-3, G6-6): a failed build stops the run; every build's and suite's exit
# status is written down (124 is a timeout); both suites' hashes are checked before anything runs; the 4 GB watchdog kills only
# this script's descendants; defects6.py runs as sealed and defects6b.py after it, with the language's own change-5 program.
# Never two at once (the drains, the pkill of servers under the temp folder). Raw output in results/e6-<lang>-<suite>.txt,
# one summary block per suite in results/e6-suites.out.
L=$1; R=/Users/robertguss/Projects/startups; M=$R/mo-lang; SU=$M/mo-wiki/plans; ES=$SU/erosion-round-suite; OUT=$ES/results
S=${SCRATCH:-/tmp/e6-scratch}; mkdir -p $S $OUT; LOG=$OUT/e6-suites.out
W=$R/mo-lang-erosion6-$L; W5=$R/mo-lang-erosion5-$L; [ $L = morun ] && W=$R/mo-lang-erosion6-mo && W5=$R/mo-lang-erosion5-mo
say() { echo "$@" | tee -a $LOG; }
die() { say "## $L STOPPED: $*"; exit 1; }
h6=$(shasum -a 256 $ES/defects6.py | cut -c1-16); h6b=$(shasum -a 256 $ES/defects6b.py | cut -c1-16)
[ "$h6" = d4dab05cc331b7fa ] || die "defects6.py is $h6, not the sealed d4dab05cc331b7fa"
[ "$h6b" = "${SEAL6B:?set SEAL6B to the sealed hash prefix of defects6b.py}" ] || die "defects6b.py is $h6b, not the sealed $SEAL6B"
say "## $L start $(date '+%Y-%m-%d %H:%M:%S %Z') load $(sysctl -n vm.loadavg) commit $(git -C $W rev-parse --short HEAD) defects6 $h6 defects6b $h6b"
build() { # name cmd...: a build whose failure stops the run
  n=$1; shift; ( "$@" ) > $OUT/e6-$L-build-$n.txt 2>&1; rc=$?; say "build $n exit=$rc"; [ $rc = 0 ] || die "build $n failed, see e6-$L-build-$n.txt"; }
case $L in
  go)   build e6 bash -c "cd $W/experiments/control-run/go/jobq && go build -o $S/jobq-e6-go ."
        build e5 bash -c "cd $W5/experiments/control-run/go/jobq && go build -o $S/jobq-e5-go ."
        build r7 bash -c "cd $R/mo-lang-control7-go/experiments/control-run/go/jobq && go build -o $S/jobq-r7-go ."
        B=$S/jobq-e6-go; CWD=$W; OLD="$S/jobq-r7-go serve {dir} --port {port}"; OLDCWD=$R/mo-lang-control7-go; B5=$S/jobq-e5-go; CWD5=$W5;;
  python) CWD=$W/experiments/control-run/python/jobq; CWD5=$W5/experiments/control-run/python/jobq; OLDCWD=$R/mo-lang-control7-python/experiments/control-run/python/jobq
        build e6 bash -c "cd $CWD && uv sync -q"; build e5 bash -c "cd $CWD5 && uv sync -q"; build r7 bash -c "cd $OLDCWD && uv sync -q"
        B="uv run jobq"; B5="uv run jobq"; OLD="uv run jobq serve {dir} --port {port}";;
  elixir) CWD=$W/experiments/control-run/elixir/jobq; CWD5=$W5/experiments/control-run/elixir/jobq; OLDCWD=$R/mo-lang-control10-elixir/experiments/control-run/elixir/jobq
        cd $W && eval "$(mise env)"
        build e6 bash -c "cd $CWD && mix deps.get && mix escript.build"; build e5 bash -c "cd $W5 && eval \"\$(mise env)\" && cd $CWD5 && mix deps.get && mix escript.build"
        [ -x $OLDCWD/jobq ] || die "no round-10 escript at $OLDCWD/jobq"
        B=$CWD/jobq; B5=$CWD5/jobq; OLD="$OLDCWD/jobq serve {dir} --port {port}";;
  mo|morun) MO=$W/toolchain/zig-out/bin/mo; G="python3 $M/toolchain/bench/step36/guard.py 600 --"
        build e6 bash -c "cd $S && $G $MO build --surface $W/examples/programs/jobq/main.mo -o jobq-e6"
        build e5 bash -c "cd $S && $G $W5/toolchain/zig-out/bin/mo build $W5/examples/programs/jobq/main.mo -o jobq-e5"
        build r7 bash -c "cd $S && $G $R/mo-lang-control7-mo/toolchain/zig-out/bin/mo build $R/mo-lang-control7-mo/examples/programs/jobq/main.mo -o jobq-r7"
        B=$S/zig-out/mo-build/jobq-e6/jobq-e6; B5=$S/zig-out/mo-build/jobq-e5/jobq-e5; CWD=$W; CWD5=$W5
        OLD="$S/zig-out/mo-build/jobq-r7/jobq-r7 serve {dir} --port {port}"; OLDCWD=$R/mo-lang-control7-mo
        [ $L = morun ] && B="$MO run $W/examples/programs/jobq/main.mo --";;
esac
SERVE="$B serve {dir} --port {port}"; VERIFY="$B verify {dir}"; COMPACT="$B compact {dir}"; PRUNE="$B prune {dir} --older-than-ms {ms}"
BENCH="$B bench {dir} --jobs {jobs} --workers {workers}"; SERVE5="$B5 serve {dir} --port {port}"; COMPACT5="$B5 compact {dir}"
export MO_CORES=1
# the out-of-memory rule: a descendant of this script past 4 GB resident is killed and named
( while true; do ps -axo pid=,ppid=,rss=,args= | python3 -c "
import sys,os,signal
rows=[l.split(None,3) for l in sys.stdin]; kids={}
for r in rows:
    if len(r)==4: kids.setdefault(r[1],[]).append(r)
todo=['$$']; mine=[]
while todo:
    for r in kids.get(todo.pop(),[]): mine.append(r); todo.append(r[0])
for pid,ppid,rss,args in mine:
    if int(rss)>4*1024*1024: os.kill(int(pid),signal.SIGKILL); print('watchdog: killed',pid,int(rss)>>10,'MB',args[:80],flush=True)
" >> $OUT/e6-$L-watchdog.txt; sleep 2; done ) & WD=$!; trap "kill $WD 2>/dev/null" EXIT
drain() { for i in $(seq 1 60); do n=$(netstat -an | grep -c TIME_WAIT); [ "$n" -lt 1500 ] && return; sleep 3; done; }
suite() { # name cmd...
  name=$1; shift; say "## $L $name $(date '+%H:%M:%S') load $(sysctl -n vm.loadavg)"
  timeout 1500 "$@" > $OUT/e6-$L-$name.txt 2>&1; rc=$?
  say "exit=$rc$([ $rc = 124 ] && echo ' (TIMED OUT: incomplete, not a result)')"
  grep -E 'passed, [0-9]+ defects|harness preconditions failed|^FAIL|^HARNESS' $OUT/e6-$L-$name.txt | tail -14 | tee -a $LOG
  grep -qE 'passed, [0-9]+ defects' $OUT/e6-$L-$name.txt || say "NO SUMMARY LINE: the suite did not reach its end"
  pkill -f 'serve /var/folders' 2>/dev/null; pkill -f 'serve /private/var' 2>/dev/null; drain
}
LF=$L; [ $L = morun ] && LF=mo
if [ -n "$ONLY" ]; then case $ONLY in defects2) suite defects2 python3 -u $ES/defects2.py --serve "$SERVE" --verify "$VERIFY" --compact "$COMPACT" --log-format $LF --cwd $CWD;; *) die "ONLY=$ONLY is not wired";; esac; say "## $L done (ONLY=$ONLY) $(date '+%H:%M:%S')"; exit 0; fi
suite regressions python3 -u $SU/control-run-8-suite/regressions.py --serve "$SERVE" --cwd $CWD
suite defects1 python3 -u $SU/control-run-8-suite/defects.py --serve "$SERVE" --cwd $CWD --old-serve "$OLD" --old-cwd $OLDCWD --compact "$COMPACT"
suite defects2 python3 -u $ES/defects2.py --serve "$SERVE" --verify "$VERIFY" --compact "$COMPACT" --log-format $LF --cwd $CWD
suite defects3 python3 -u $ES/defects3.py --serve "$SERVE" --verify "$VERIFY" --cwd $CWD
suite defects4 python3 -u $ES/defects4.py --serve "$SERVE" --verify "$VERIFY" --compact "$COMPACT" --cwd $CWD
suite defects5 python3 -u $ES/defects5.py --serve "$SERVE" --verify "$VERIFY" --compact "$COMPACT" --cwd $CWD
suite defects6-sealed python3 -u $ES/defects6.py --serve "$SERVE" --verify "$VERIFY" --compact "$COMPACT" --prune "$PRUNE" --bench "$BENCH" --cwd $CWD
suite defects6b python3 -u $ES/defects6b.py --serve "$SERVE" --verify "$VERIFY" --compact "$COMPACT" --prune "$PRUNE" --bench "$BENCH" --cwd $CWD --old5-serve "$SERVE5" --old5-compact "$COMPACT5" --old5-cwd $CWD5
say "## $L done $(date '+%H:%M:%S')"
