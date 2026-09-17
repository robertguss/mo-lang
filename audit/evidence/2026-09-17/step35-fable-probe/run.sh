#!/bin/bash
S=/tmp/claude-1000/-home-exedev-Projects-mo-lang/aca79dff-6e6e-4946-9645-b1abe7522f67/scratchpad/probe
MO=/home/exedev/Projects/mo-lang/toolchain/zig-out/bin/mo
cd $S
echo "== mo run probe"; /usr/bin/time -f "rss_kib %M wall %e" timeout 600 $MO run probe.mo > run.out 2> run.err; echo "exit $?"; tail -2 run.err
echo "== mo build probe"; timeout 900 $MO build probe.mo -o probe 2>&1 | tail -2; echo "exit ${PIPESTATUS[0]}"
echo "== binary probe"; /usr/bin/time -f "rss_kib %M wall %e" timeout 600 ./zig-out/mo-build/probe/probe > bin.out 2> bin.err; echo "exit $?"; tail -2 bin.err
echo "== capture (expect MO0409)"; timeout 60 $MO run capture.mo 2>&1 | head -4; echo "exit ${PIPESTATUS[0]}"
echo "== crash under mo run"; timeout 60 $MO run crash.mo 2>&1 | head -6; echo "exit ${PIPESTATUS[0]}"
echo "== crash as binary"; timeout 300 $MO build crash.mo -o crash >/dev/null 2>&1; timeout 60 ./zig-out/mo-build/crash/crash 2>&1 | head -6; echo "exit ${PIPESTATUS[0]}"
echo "== probe tests under mo test"; timeout 300 $MO test probe.mo 2>&1 | tail -2
echo DONE
