#!/usr/bin/env bash
# The program-level check: `jobq check` through real sockets, then a compaction, then a
# second `jobq check` on the same directory after the restart.
set -euo pipefail
cd "$(dirname "$0")"
work=$(mktemp -d)
actual=$(mktemp)
trap 'rm -rf "$work" "$actual"' EXIT

{
  timeout 60 uv run --quiet jobq check "$work" checks/first.txt
  timeout 60 uv run --quiet jobq compact "$work"
  timeout 60 uv run --quiet jobq check "$work" checks/second.txt
} | sed -E \
  -e 's/"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}Z"/"<time>"/g' \
  -e 's/"uptime_ms":[0-9]+/"uptime_ms":<n>/' \
  -e "s|$work|<dir>|" \
  -e 's/: [0-9]+ records to/: <n> records to/' > "$actual"
diff -u checks/expected.txt "$actual"

set +e
timeout 60 uv run --quiet jobq serve "$work/missing" --port 0 2> /dev/null
code=$?
timeout 60 uv run --quiet jobq bogus 2> /dev/null
usage=$?
set -e
[ "$code" -eq 1 ] || { echo "check.sh: serve on a missing dir exited $code, expected 1"; exit 1; }
[ "$usage" -eq 2 ] || { echo "check.sh: a usage error exited $usage, expected 2"; exit 1; }

echo "check.sh: ok"
