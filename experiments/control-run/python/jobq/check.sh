#!/usr/bin/env bash
# The program-level check: `jobq check` through real sockets, then a compaction, then a
# second `jobq check` on the same directory after the restart, with `jobq verify` reading
# the folder between them. Then the same on a copy of a folder the round 7 program served:
# it opens, takes the new routes, and compacts to a log with no old name in it. Last, a
# folder holding one ill-formed record, which no command will serve. In between, `jobq serve`
# with the chaos switch on: the board restarts once, `restarts` counts it, the second failure
# spends the budget and serve exits 70, and the folder verifies with every write in it.
# Last in the transcript, `jobq serve --retain-ms 1000`: a keyed create and its repeat, a
# finished job archived and read by id, then a stop, a compaction, and a start that still
# know the archived job and its key.
# Change 5: a check of handoffs and renames, a verify, a compaction, and a second check that
# finds the handed-off lease and the renamed queue as they were.
# Change 6: the prune, rename, and reopen sequence of checks/sequence.py, twice.
set -euo pipefail
cd "$(dirname "$0")"
work=$(mktemp -d)
old=$(mktemp -d)
bad=$(mktemp -d)
chaos=$(mktemp -d)
arch=$(mktemp -d)
moved=$(mktemp -d)
actual=$(mktemp)
trap 'rm -rf "$work" "$old" "$bad" "$chaos" "$arch" "$moved" "$actual"' EXIT
# The round 7 folder, its times moved to now: its finished jobs are fresh, so the default
# day's retention does not archive them however long ago the fixture was written.
python3 - tests/fixtures/round7/jobs.log "$old/jobs.log" <<'PY'
import re, sys, time
text = open(sys.argv[1], encoding="utf-8").read()
stamps = [int(n) for n in re.findall(r'"\w+_ms":(\d{13})', text)]
delta = int(time.time() * 1000) - max(stamps)
moved = re.sub(r'("\w+_ms":)(\d{13})', lambda m: m[1] + str(int(m[2]) + delta), text)
open(sys.argv[2], "w", encoding="utf-8").write(moved)
PY

# `checks/chaos.txt` through `jobq client`, one process per line, against a served folder.
play_chaos() {
  timeout 60 uv run --quiet jobq serve "$chaos/data" --port 0 --crash-every 3 \
    --max-restarts 1 --restart-window 60 2> "$chaos/serve.err" &
  local pid=$! line="" port="" token method path body
  for _ in $(seq 100); do
    line=$(head -n 1 "$chaos/serve.err" 2> /dev/null || true)  # the file may not exist yet
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

# A script through `jobq client` against `jobq serve --retain-ms 1000`, one process per
# line; a `sleep S` line waits. The service is stopped with SIGTERM at the end.
play_archive() {
  local script=$1 line="" port="" token method path body
  timeout 60 uv run --quiet jobq serve "$arch/data" --port 0 --retain-ms 1000 \
    2> "$arch/serve.err" &
  local pid=$!
  for _ in $(seq 100); do
    line=$(head -n 1 "$arch/serve.err" 2> /dev/null || true)  # the file may not exist yet
    [ -n "$line" ] && break
    sleep 0.1
  done
  port=${line##*:}
  while IFS= read -r line; do
    case "$line" in ''|'#'*) continue ;; 'sleep '*) ${line}; continue ;; esac
    read -r token method path body <<< "$line"
    echo "> $line"
    timeout 60 uv run --quiet jobq client 127.0.0.1 "$port" "$token" "$method" "$path" \
      ${body:+"$body"}
  done < "$script"
  # SIGTERM to the service itself, the leaf under timeout and uv: a signal to the wrapper
  # races its forwarding and can end it with 143 before the service's own 0.
  local leaf=$pid next
  while next=$(pgrep -P "$leaf" | head -n 1) && [ -n "$next" ]; do leaf=$next; done
  kill -TERM "$leaf"
  local code=0
  wait "$pid" || code=$?
  echo "serve exited $code"
}
mkdir "$arch/data"
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
  play_archive checks/archive-first.txt
  timeout 60 uv run --quiet jobq verify "$arch/data"
  timeout 60 uv run --quiet jobq compact "$arch/data"
  play_archive checks/archive-second.txt
  timeout 60 uv run --quiet jobq compact "$arch/data"
  timeout 60 uv run --quiet jobq verify "$arch/data"
  timeout 60 uv run --quiet jobq check "$moved" checks/handoff-rename-first.txt
  timeout 60 uv run --quiet jobq verify "$moved"
  timeout 60 uv run --quiet jobq compact "$moved"
  timeout 60 uv run --quiet jobq check "$moved" checks/handoff-rename-second.txt
  timeout 60 uv run --quiet jobq verify "$moved"
} | sed -E \
  -e 's/"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}Z"/"<time>"/g' \
  -e 's/"uptime_ms":[0-9]+/"uptime_ms":<n>/' \
  -e "s|$work|<dir>|" \
  -e "s|$old|<old>|" \
  -e "s|$arch/data|<arch>|" \
  -e "s|$moved|<moved>|" \
  -e 's/: [0-9]+ records to/: <n> records to/' > "$actual"
diff -u checks/expected.txt "$actual"
grep -q '"kind":"rename"' "$moved/jobs.log" ||
  { echo "check.sh: the second run's renames are not in the log"; exit 1; }
timeout 60 uv run --quiet jobq compact "$moved" > /dev/null
if grep -q '"kind":"rename"' "$moved/jobs.log"; then
  echo "check.sh: the compacted log still holds a rename record"
  exit 1
fi
if grep -q attempts "$old/jobs.log"; then
  echo "check.sh: the compacted round 7 log still holds an old name"
  exit 1
fi

# Change 6: the sequence (checks/sequence.py, every expected answer in it) on a fresh folder
# and on a copy of the folder the change-5 program wrote, then a prune from the command line.
seq_fresh=$(mktemp -d)
seq_old=$(mktemp -d)
trap 'rm -rf "$work" "$old" "$bad" "$chaos" "$arch" "$moved" "$actual" "$seq_fresh" "$seq_old"' EXIT
cp tests/fixtures/change5/jobs.log tests/fixtures/change5/jobq.archive "$seq_old/"
timeout 300 uv run --quiet python checks/sequence.py "$seq_fresh" > /dev/null
timeout 300 uv run --quiet python checks/sequence.py "$seq_old" > /dev/null
pruned=$(timeout 60 uv run --quiet jobq prune "$seq_old" --older-than-ms 1000)
[ "$pruned" = "jobq: pruned $seq_old: pruned 1, remaining 0" ] ||
  { echo "check.sh: jobq prune said: $pruned"; exit 1; }
timeout 60 uv run --quiet jobq verify "$seq_old" > /dev/null

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
