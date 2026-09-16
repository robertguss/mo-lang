#!/usr/bin/env bash
# The program-level check: `jobq check` through real sockets, then a compaction, then a
# second `jobq check` on the same directory after the restart, with `jobq verify` reading
# the folder between them. Then the same on a copy of a folder the round 7 program served:
# it opens, takes the new routes, and compacts to a log with no old name in it. Last, a
# folder holding one ill-formed record, which no command will serve. In between, `jobq serve`
# with the chaos switch on: the board restarts once, `restarts` counts it, the second failure
# spends the budget and serve exits 70, and the folder verifies with every write in it.
set -euo pipefail
cd "$(dirname "$0")"
work=$(mktemp -d)
old=$(mktemp -d)
bad=$(mktemp -d)
chaos=$(mktemp -d)
actual=$(mktemp)
trap 'rm -rf "$work" "$old" "$bad" "$chaos" "$actual"' EXIT
cp tests/fixtures/round7/jobs.log "$old/jobs.log"

# `checks/chaos.txt` through `jobq client`, one process per line, against a served folder.
play_chaos() {
  timeout 60 uv run --quiet jobq serve "$chaos/data" --port 0 --crash-every 3 \
    --max-restarts 1 --restart-window 60 2> "$chaos/serve.err" &
  local pid=$! line="" port="" token method path body
  for _ in $(seq 100); do
    line=$(head -n 1 "$chaos/serve.err")
    [ -n "$line" ] && break
    sleep 0.1
  done
  port=${line##*:}
  while IFS= read -r line; do
    case "$line" in ''|'#'*) continue ;; esac
    read -r token method path body <<< "$line"
    echo "> $line"
    timeout 60 uv run --quiet jobq client 127.0.0.1 "$port" "$token" "$method" "$path" \
      ${body:+"$body"}
  done < checks/chaos.txt
  local code=0
  wait "$pid" || code=$?
  echo "serve exited $code"
  echo "board failures logged: $(grep -c "rebuilding it from the log" "$chaos/serve.err")"
  timeout 60 uv run --quiet jobq verify "$chaos/data"
}
mkdir "$chaos/data"
cp tests/fixtures/illformed/jobs.log "$bad/jobs.log"

{
  timeout 60 uv run --quiet jobq check "$work" checks/first.txt
  timeout 60 uv run --quiet jobq verify "$work"
  timeout 60 uv run --quiet jobq compact "$work"
  timeout 60 uv run --quiet jobq verify "$work"
  timeout 60 uv run --quiet jobq check "$work" checks/second.txt
  timeout 60 uv run --quiet jobq check "$old" checks/round7.txt
  timeout 60 uv run --quiet jobq verify "$old"
  timeout 60 uv run --quiet jobq compact "$old"
  timeout 60 uv run --quiet jobq check "$old" checks/round7-after.txt
  play_chaos
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
refusal=$(timeout 60 uv run --quiet jobq verify "$bad" 2>&1 > /dev/null)
refused=$?
timeout 60 uv run --quiet jobq serve "$bad" --port 0 2> /dev/null
unserved=$?
timeout 60 uv run --quiet jobq compact "$bad" 2> /dev/null
uncompacted=$?
set -e
[ "$code" -eq 1 ] || { echo "check.sh: serve on a missing dir exited $code, expected 1"; exit 1; }
[ "$usage" -eq 2 ] || { echo "check.sh: a usage error exited $usage, expected 2"; exit 1; }
[ "$refused" -eq 1 ] || { echo "check.sh: verify of an ill-formed folder exited $refused"; exit 1; }
[ "$unserved" -eq 1 ] || { echo "check.sh: serve of an ill-formed folder exited $unserved"; exit 1; }
[ "$uncompacted" -eq 1 ] || { echo "check.sh: compact of it exited $uncompacted"; exit 1; }
want="jobq: $bad: record j_2: a leased job has no run_at"
[ "$refusal" = "$want" ] || { echo "check.sh: the refusal said: $refusal"; exit 1; }
# The refused folder is left as it was found: only the lock file every open makes is added.
cmp -s "$bad/jobs.log" tests/fixtures/illformed/jobs.log ||
  { echo "check.sh: a refused folder had its log rewritten"; exit 1; }

echo "check.sh: ok"
