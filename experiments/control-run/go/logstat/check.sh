#!/usr/bin/env bash
# The program-level check: build logstat, run it over fixture/, and diff the
# text and JSON reports against expected.txt and expected.json.
set -euo pipefail
cd "$(dirname "$0")"
bin="$(mktemp -d)"
trap 'rm -rf "$bin"' EXIT
timeout 120 go build -o "$bin/logstat" .
timeout 30 "$bin/logstat" fixture > "$bin/out.txt"
timeout 30 "$bin/logstat" fixture --json > "$bin/out.json"
diff -u expected.txt "$bin/out.txt"
diff -u expected.json "$bin/out.json"
echo "check.sh: ok"
