#!/bin/sh
# Program-level check: run logstat over the fixture and diff against expected.txt and expected.json.
set -eu
cd "$(dirname "$0")"
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT

python3 logstat.py fixture >"$out/text"
diff -u expected.txt "$out/text"

python3 logstat.py fixture --json >"$out/json"
diff -u expected.json "$out/json"

echo "check.sh: ok"
