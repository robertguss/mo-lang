#!/bin/sh
# Program-level check: run logstat over fixture/ and diff the text report
# against expected.txt and the JSON summary against expected.json.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

cd "$here"
go build -o "$work/logstat" .

"$work/logstat" fixture >"$work/out.txt"
diff -u expected.txt "$work/out.txt"

"$work/logstat" fixture --json >"$work/out.json"
diff -u expected.json "$work/out.json"

echo "check.sh: ok"
