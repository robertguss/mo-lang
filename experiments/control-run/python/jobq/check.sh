#!/usr/bin/env bash
# The program-level check: `jobq check` through real sockets, then a compaction, then a
# second `jobq check` on the same directory after the restart. Then the same on a copy of a
# folder the round 7 program served, before the tries rename: it opens, takes the new
# routes, and compacts to a log with no old name in it.
set -euo pipefail
cd "$(dirname "$0")"
work=$(mktemp -d)
old=$(mktemp -d)
actual=$(mktemp)
trap 'rm -rf "$work" "$old" "$actual"' EXIT
cp tests/fixtures/round7/jobs.log "$old/jobs.log"

{
  timeout 60 uv run --quiet jobq check "$work" checks/first.txt
  timeout 60 uv run --quiet jobq compact "$work"
  timeout 60 uv run --quiet jobq check "$work" checks/second.txt
  timeout 60 uv run --quiet jobq check "$old" checks/round7.txt
  timeout 60 uv run --quiet jobq compact "$old"
  timeout 60 uv run --quiet jobq check "$old" checks/round7-after.txt
} | sed -E \
  -e 's/"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}Z"/"<time>"/g' \
  -e 's/"uptime_ms":[0-9]+/"uptime_ms":<n>/' \
  -e "s|$work|<dir>|" \
  -e "s|$old|<old>|" \
  -e 's/: [0-9]+ records to/: <n> records to/' > "$actual"
diff -u checks/expected.txt "$actual"
if grep -q attempts "$old/jobs.log"; then
  echo "check.sh: the compacted round 7 log still holds an old name"
  exit 1
fi

set +e
timeout 60 uv run --quiet jobq serve "$work/missing" --port 0 2> /dev/null
code=$?
timeout 60 uv run --quiet jobq bogus 2> /dev/null
usage=$?
set -e
[ "$code" -eq 1 ] || { echo "check.sh: serve on a missing dir exited $code, expected 1"; exit 1; }
[ "$usage" -eq 2 ] || { echo "check.sh: a usage error exited $usage, expected 2"; exit 1; }

echo "check.sh: ok"
