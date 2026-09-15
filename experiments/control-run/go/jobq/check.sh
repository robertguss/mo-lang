#!/usr/bin/env bash
# Program-level check for jobq. 1: `jobq check` plays testdata/check.script
# through a real socket and the output must equal testdata/check.expected.
# 2: `jobq serve` and `jobq client` as separate processes: create, lease,
# stop with SIGTERM, start again, and the lease is still there; then compact.
# 3: a folder the previous version served (testdata/v1, written before the
# tries rename) opens, and compact leaves no old name in its log.
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
serve() { # serve <dir>
  timeout 60 "$jobq" serve "$1" --port "$port" 2>> "$tmp/serve.err" &
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
stop
echo "check.sh: ok"
