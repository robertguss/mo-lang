#!/bin/bash
# The build and check commands of part A, collected here after they were run by hand on 18 Sep 2026, 07:52-08:05 UTC.
# One compiler for every binary: toolchain/zig-out/bin/mo on main at 972c872 (sha256 26d92b56...; `zig build` found it current).
S=/tmp/claude-1000/-home-exedev-Projects-mo-lang/b2557fa4-9d5d-4e16-b574-25ec6f9b23b8/scratchpad/g4c
M=/home/exedev/Projects/mo-lang/toolchain/zig-out/bin/mo
cd /home/exedev/Projects/mo-lang && git worktree add ../mo-lang-erosion4-control -b erosion4-control erosion4-mo
cd ../mo-lang-erosion4-control
# variant cheap: board.mo line 383 (sweep's third ensures) replaced; see variant-cheap.diff
# mo test --write on board.mo, then on every jobq file mo check named stale (api, main, queue, server);
# queue.mo and server.mo with --sim 100 so their verified: lines keep the sim counts erosion4-mo had
$M test --write examples/programs/jobq/board.mo
for f in api main; do $M test --write examples/programs/jobq/$f.mo; done
for f in queue server; do $M test --write --sim 100 examples/programs/jobq/$f.mo; done
$M test --write examples/programs/jobq/main.mo    # again, after queue and server
for f in examples/programs/jobq/*.mo; do $M check $f || echo FAIL $f; done
git commit ...    # 8358bb2
$M build examples/programs/jobq/main.mo && $M build examples/programs/jobq/main.mo -o jobq-surface --surface
mkdir -p $S/bin/cheap && cp zig-out/mo-build/jobq/jobq zig-out/mo-build/jobq-surface/jobq-surface $S/bin/cheap/
# variant none: the line deleted; the same test --write sequence and checks; commit 5cbd3eb; the same build into $S/bin/none/
for g in 3 4; do
  cd /home/exedev/Projects/mo-lang-erosion$g-mo
  $M build examples/programs/jobq/main.mo && $M build examples/programs/jobq/main.mo -o jobq-surface --surface
  mkdir -p $S/bin/gen$g && cp zig-out/mo-build/jobq/jobq zig-out/mo-build/jobq-surface/jobq-surface $S/bin/gen$g/
done
# sha256 of the four jobq binaries:
# gen3  e47e097ca34cd58b3122edd1b754768e635a96be5ec607d94475f6f52a7f08c3
# gen4  cf682890176cea207dab33356b3dc59132777e2ff48bd7d4c61f9feb18ecd3c6
# cheap 4666f8e0579e5698962ffe587507ea9c9f47333314bf7c33b3f1e6f789c90b3f
# none  8b30f13b789c167253a329cc82b84791cf61a299085c972295292f7d5288f132
