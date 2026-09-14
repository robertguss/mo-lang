#!/bin/sh
# The program-level check: logstat over fixture/ against expected.txt and expected.json.
set -eu
cd "$(dirname "$0")"
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT

timeout 60 uv run --quiet logstat fixture > "$out/actual.txt"
timeout 60 uv run --quiet logstat fixture --json > "$out/actual.json"
diff -u expected.txt "$out/actual.txt"
diff -u expected.json "$out/actual.json"

set +e
timeout 60 uv run --quiet logstat fixture --top 0 2> "$out/usage.txt"
code=$?
set -e
[ "$code" -eq 2 ] || { echo "check.sh: --top 0 exited $code, expected 2"; exit 1; }
[ "$(wc -l < "$out/usage.txt")" -eq 1 ] || { echo "check.sh: usage error is not one line"; exit 1; }

set +e
timeout 60 uv run --quiet logstat "$out" 2> /dev/null
code=$?
set -e
[ "$code" -eq 1 ] || { echo "check.sh: empty dir exited $code, expected 1"; exit 1; }

echo "check.sh: ok"
