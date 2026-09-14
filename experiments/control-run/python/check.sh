#!/bin/sh
# Program-level check: run logstat over the fixture and diff against the expected outputs.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT

python3 "$here/logstat.py" "$here/fixture" > "$out/expected.txt"
diff -u "$here/expected.txt" "$out/expected.txt"

python3 "$here/logstat.py" "$here/fixture" --json > "$out/expected.json"
diff -u "$here/expected.json" "$out/expected.json"

echo "check.sh: text and JSON match"
