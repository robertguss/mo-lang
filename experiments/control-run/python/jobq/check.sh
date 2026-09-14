#!/usr/bin/env bash
# Program-level check: `jobq check` plays check/script.txt through a real socket; the transcript
# must match check/expected.txt exactly.
set -euo pipefail
cd "$(dirname "$0")"

store=$(mktemp -d)
actual=$(mktemp)
trap 'rm -rf "$store" "$actual"' EXIT

timeout 120 uv run --quiet jobq check "$store" check/script.txt >"$actual"
diff -u check/expected.txt "$actual"
echo "check.sh: ok"
