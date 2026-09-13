#!/bin/sh
# Program-level check: run logstat over fixture/ and diff against the expected reports.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
actual=$(mktemp -d)
trap 'rm -rf "$actual"' EXIT

python3 "$here/logstat.py" "$here/fixture" > "$actual/expected.txt"
python3 "$here/logstat.py" "$here/fixture" --json > "$actual/expected.json"

diff -u "$here/expected.txt" "$actual/expected.txt"
diff -u "$here/expected.json" "$actual/expected.json"
echo "check.sh: text and JSON reports match"
