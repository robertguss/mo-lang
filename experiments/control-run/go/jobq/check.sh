#!/usr/bin/env bash
# Program-level check for jobq. 1: `jobq check` plays testdata/check.script
# through a real socket and the output must equal testdata/check.expected.
# 2: `jobq serve` and `jobq client` as separate processes: create, lease,
# stop with SIGTERM, start again, and the lease is still there; then compact.
# 3: a folder the previous version served (testdata/v1, written before the
# tries rename) opens, and compact leaves no old name in its log. 4: `jobq
# verify` on the folders the run leaves behind, and serve, compact, and
# verify all refusing testdata/ill, whose second record is a leased job with
# no worker. 5: GET /queues through the served process. 6: the chaos switch
# on the served process: a write fails after reaching the disk, the service
# restarts itself and counts it in /health; with a budget of 1 the second
# failure inside the window exits 70 and the folder verifies. 7: keys and
# the archive on the served process, through a restart and a compaction.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"
pid=""
cleanup() { [ -n "$pid" ] && kill "$pid" 2>/dev/null; rm -rf "$tmp"; }
trap cleanup EXIT
(cd "$here/.." && timeout 120 go build -o "$tmp/jobq" ./jobq)
jobq="$tmp/jobq"

mkdir "$tmp/check"
timeout 60 "$jobq" check "$tmp/check" "$here/testdata/check.script" > "$tmp/check.out"
diff -u "$here/testdata/check.expected" "$tmp/check.out"

port="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')"
client() { timeout 10 "$jobq" client 127.0.0.1 "$port" "$@"; }
serve() { # serve <dir> [options]
  local dir="$1"; shift
  timeout 60 "$jobq" serve "$dir" --port "$port" "$@" 2>> "$tmp/serve.err" &
  pid=$!
  for _ in $(seq 100); do
    if client - GET /health > /dev/null 2>&1; then return 0; fi
    sleep 0.05
  done
  echo "check.sh: jobq serve did not answer" >&2; cat "$tmp/serve.err" >&2; exit 1
}
stop() { kill -TERM "$pid"; wait "$pid"; pid=""; }
expect() { # expect <status> <substring> <client args...>
  local status="$1" substring="$2"; shift 2
  local out; out="$(client "$@")"
  if [ "$(head -n 1 <<< "$out")" != "$status" ] || [[ "$out" != *"$substring"* ]]; then
    echo "check.sh: client $* gave:" >&2; echo "$out" >&2; exit 1
  fi
}

mkdir "$tmp/serve"
serve "$tmp/serve"
expect 201 '"id":"j_1"' prod POST /jobs '{"queue":"emails","payload":"hi","max_tries":2}'
expect 200 '"worker":"w1"' w1 POST /queues/emails/lease '{"lease_ms":60000}'
stop
serve "$tmp/serve"
expect 200 '"state":"leased"' prod GET /jobs/j_1
expect 409 'error' w2 POST /jobs/j_1/ack
expect 200 '"state":"done"' w1 POST /jobs/j_1/ack
stop
timeout 30 "$jobq" compact "$tmp/serve"
lines="$(python3 -c 'import sys; print(sum(1 for _ in open(sys.argv[1])))' "$tmp/serve/jobq.log")"
[ "$lines" = 2 ] || { echo "check.sh: compacted log has $lines lines, want 2" >&2; exit 1; }
serve "$tmp/serve"
expect 200 '"state":"done"' prod GET /jobs/j_1
stop

mkdir "$tmp/old"
cp "$here/testdata/v1/jobq.log" "$tmp/old/jobq.log"
grep -q '"max_attempts"' "$tmp/old/jobq.log" || {
  echo "check.sh: testdata/v1 is not a log in the old shape" >&2; exit 1; }
serve "$tmp/old"
expect 200 '"state":"done"' prod GET /jobs/j_1          # acked by the old service
expect 200 '"tries":1' prod GET /jobs/j_4               # attempts read as tries
expect 200 '"state":"queued"' prod GET /jobs/j_5        # its lease ran out
expect 200 '"state":"dead"' prod GET /jobs/j_6          # on its last try
expect 404 'no such job' prod GET /jobs/j_3             # deleted by the old service
expect 200 '"tries":0' prod POST /jobs/j_6/retry
expect 201 '"state":"scheduled"' prod POST /jobs '{"queue":"push","payload":"later","max_tries":1,"delay_ms":60000}'
stop
timeout 30 "$jobq" compact "$tmp/old"
if grep -q 'attempts' "$tmp/old/jobq.log"; then
  echo "check.sh: compact left an old name in the log" >&2; exit 1
fi
serve "$tmp/old"
expect 200 '"state":"queued"' prod GET /jobs/j_6
expect 200 '"scheduled":1' - GET /health
expect 200 '{"name":"push","queued":3,"scheduled":1,"leased":0,"done":0,"dead":0}' prod GET /queues
expect 401 'error' - GET /queues
stop

# 4: verify on the folders this run leaves behind, and the ill-formed one.
timeout 30 "$jobq" verify "$tmp/serve" | grep -q '^1 jobs: queued 0, scheduled 0, leased 0, done 1, dead 0; next id j_2; archived 0$' || {
  echo "check.sh: verify of the served folder printed the wrong line" >&2; exit 1; }
timeout 30 "$jobq" verify "$tmp/old" > /dev/null
mkdir "$tmp/ill"
cp "$here/testdata/ill/jobq.log" "$tmp/ill/jobq.log"
want="jobq: $tmp/ill: record j_2: a leased job has a worker"
for cmd in verify serve compact; do
  if out="$(timeout 30 "$jobq" "$cmd" "$tmp/ill" 2>&1)"; then
    echo "check.sh: jobq $cmd served an ill-formed folder" >&2; exit 1
  fi
  [ "$out" = "$want" ] || { echo "check.sh: jobq $cmd said '$out', want '$want'" >&2; exit 1; }
done

# 6: the chaos switch and the restart budget.
mkdir "$tmp/chaos"
serve "$tmp/chaos" --crash-every 2 --max-restarts 1 --restart-window 60
expect 200 '"restarts":0' - GET /health
expect 201 '"id":"j_1"' prod POST /jobs '{"queue":"c","payload":"one","max_tries":1}'
expect 503 'error' prod POST /jobs '{"queue":"c","payload":"two","max_tries":1}'
for _ in $(seq 100); do
  if client - GET /health 2>/dev/null | grep -q '"restarts":1'; then break; fi
  sleep 0.01
done
expect 200 '"restarts":1' - GET /health
expect 200 '"payload":"two"' prod GET /jobs/j_2
expect 201 '"id":"j_3"' prod POST /jobs '{"queue":"c","payload":"three","max_tries":1}'
expect 503 'error' prod POST /jobs '{"queue":"c","payload":"four","max_tries":1}'
code=0; wait "$pid" || code=$?; pid=""
[ "$code" = 70 ] || { echo "check.sh: serve past its budget exited $code, want 70" >&2; cat "$tmp/serve.err" >&2; exit 1; }
timeout 30 "$jobq" verify "$tmp/chaos" | grep -q '^4 jobs: queued 4,' || {
  echo "check.sh: verify after exit 70 printed the wrong line" >&2; exit 1; }
if timeout 10 "$jobq" compact "$tmp/chaos" --crash-every 1 2> /dev/null; then
  echo "check.sh: compact took --crash-every" >&2; exit 1
fi

# 7: idempotent creates and the archive on the served process: a keyed
# create twice, a job archived after --retain-ms and read by id, both
# surviving a stop and start and a compaction, and verify counting it.
mkdir "$tmp/arch"
serve "$tmp/arch" --retain-ms 1000
expect 201 '"key":"once"' prod POST /jobs '{"queue":"k","key":"once","payload":"p","max_tries":1}'
expect 200 '"id":"j_1"' prod POST /jobs '{"queue":"k","key":"once","payload":"other","max_tries":1}'
expect 200 '"worker":"w1"' w1 POST /queues/k/lease
expect 200 '"state":"done"' w1 POST /jobs/j_1/ack
sleep 1.2
expect 200 '"archived":1' - GET /health
expect 200 '"archived_at"' prod GET /jobs/j_1
expect 200 '{"jobs":[]}' prod GET /jobs?queue=k
expect 409 'archived' prod POST /jobs/j_1/retry
stop
[ -s "$tmp/arch/jobq.archive" ] || { echo "check.sh: no archive file" >&2; exit 1; }
timeout 30 "$jobq" verify "$tmp/arch" | grep -q '^0 jobs: .*; next id j_2; archived 1$' || {
  echo "check.sh: verify of the archived folder printed the wrong line" >&2; exit 1; }
timeout 30 "$jobq" compact "$tmp/arch"
if grep -q '"j_1"' "$tmp/arch/jobq.log"; then
  echo "check.sh: compact left an archived job in the log" >&2; exit 1
fi
serve "$tmp/arch"
expect 200 '"archived_at"' prod GET /jobs/j_1
expect 200 '"id":"j_1"' prod POST /jobs '{"queue":"k","key":"once","payload":"p","max_tries":1}'
expect 204 '' prod DELETE /jobs/j_1
expect 201 '"id":"j_2"' prod POST /jobs '{"queue":"k","key":"once","payload":"p","max_tries":1}'
stop
timeout 30 "$jobq" verify "$tmp/arch" | grep -q '^1 jobs: queued 1, .*; archived 0$' || {
  echo "check.sh: verify after the archived delete printed the wrong line" >&2; exit 1; }
if timeout 10 "$jobq" serve "$tmp/arch" --retain-ms 999 2> /dev/null; then
  echo "check.sh: serve took --retain-ms 999" >&2; exit 1
fi
echo "check.sh: ok"
