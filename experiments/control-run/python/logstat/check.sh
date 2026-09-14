#!/usr/bin/env bash
# Program-level check: logstat over fixture/ must match expected.txt and expected.json exactly.
set -euo pipefail
cd "$(dirname "$0")"

actual_text=$(mktemp)
actual_json=$(mktemp)
trap 'rm -f "$actual_text" "$actual_json"' EXIT

timeout 60 uv run --quiet logstat fixture >"$actual_text"
timeout 60 uv run --quiet logstat fixture --json >"$actual_json"

diff -u expected.txt "$actual_text"
diff -u expected.json "$actual_json"
echo "check.sh: ok"
