#!/bin/bash
# usage: r9-setup.sh <m>      three worktrees for model <m> from round 7's branches, the mo binary copied in
# run from the repo root; prints the three worktree paths
set -e
R=$(pwd); M=$1
for L in mo go python; do
  W=$R/../mo-lang-r9-$M-$L
  [ -d "$W" ] || git worktree add -q "$W" -b r9-$M-$L control7-$L
  echo "$W"
done
mkdir -p "$R/../mo-lang-r9-$M-mo/toolchain/zig-out/bin"
cp "$R/toolchain/zig-out/bin/mo" "$R/../mo-lang-r9-$M-mo/toolchain/zig-out/bin/mo"
