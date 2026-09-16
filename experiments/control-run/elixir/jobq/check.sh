#!/bin/sh
# The program-level check: build the escript, serve on a free port, play
# script/check.script through `jobq check` over a real socket, and diff the
# transcript against script/expected.txt.
#
# Timestamps and the uptime are what one run does not share with the next, so
# they are the two things the transcript normalizes away.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

cd "$here"
mix escript.build >/dev/null

mkdir "$work/data"
timeout 300 ./jobq check "$work/data" script/check.script >"$work/raw.txt"
python3 script/normalize.py <"$work/raw.txt" >"$work/out.txt"
diff -u script/expected.txt "$work/out.txt"

echo "check.sh: ok"
