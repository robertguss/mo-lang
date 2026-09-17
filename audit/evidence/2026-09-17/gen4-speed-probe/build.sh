#!/bin/bash
MO=/home/exedev/Projects/mo-lang/toolchain/zig-out/bin/mo
for g in 3 4; do
  cd /home/exedev/Projects/mo-lang-erosion$g-mo || exit 1
  echo "== build gen $g"; time timeout 900 $MO build examples/programs/jobq/main.mo 2>&1 | tail -3
  ls -la zig-out/mo-build/jobq/jobq; nm zig-out/mo-build/jobq/jobq 2>/dev/null | wc -l
done
echo BUILD-DONE
