#!/bin/sh
# Program-level check: run logstat over the fixture, diff against the expected outputs.
set -eu
cd "$(dirname "$0")"
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT

python3 logstat.py fixture > "$out/text.txt"
diff -u expected.txt "$out/text.txt"

python3 logstat.py fixture --json > "$out/summary.json"
diff -u expected.json "$out/summary.json"

if grep -q '4111111111111111' "$out/text.txt" "$out/summary.json"; then
  echo "check: a card number reached stdout" >&2
  exit 1
fi

echo "check: ok"
