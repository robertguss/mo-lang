#!/bin/bash
# The rebuild probe: ten hand-written logs (rebuild-cases/) played through a variant's whole program with
# `jobq check`, so the board rebuilt from a log is compared too, which the sampler cannot reach.
# usage: OUT=<dir> rebuild.sh <name> <jobq-dir>   output in $OUT/<name>/<case>.out
S=$(cd "$(dirname "$0")" && pwd)/rebuild-cases; OUT=${OUT:-$S/../rebuild-out}
MO=/home/exedev/Projects/mo-lang-sampling/toolchain/zig-out/bin/mo
name=$1; dir=$2; mkdir -p $OUT/$name
for c in $S/*/; do
  cn=$(basename $c); w=$(mktemp -d); cp -r $c $w/d
  (cd $dir && timeout 60 $MO run main.mo -- check $w/d $S/session.txt > $OUT/$name/$cn.out 2>&1; echo "exit $?" >> $OUT/$name/$cn.out)
  rm -rf $w
done
echo "$name done"
