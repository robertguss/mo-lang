#!/bin/sh
# The program-level check.
#
# One: build the escript, serve on a free port and play script/check.script
# through `jobq check` over a real socket, and diff the transcript against
# script/expected.txt. Timestamps and the uptime are what one run does not
# share with the next, so they are the two things the transcript normalizes.
#
# Two: the other three commands against a `jobq serve` of their own — the
# client over a real socket, compact on the log it wrote, and the exit codes
# the spec asks for.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
cd "$here"

port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')
served=""

cleanup() {
  [ -n "$served" ] && kill "$served" 2>/dev/null || true
  rm -rf "$work"
}
trap cleanup EXIT

fail() {
  echo "check.sh: $1" >&2
  exit 1
}

expect_status() {
  want=$1
  shift
  set +e
  "$@" >"$work/out" 2>"$work/err"
  got=$?
  set -e
  [ "$got" = "$want" ] || fail "expected exit $want from '$*', got $got"
}

expect_body() {
  grep -q -- "$1" "$work/out" || fail "expected '$1' in: $(cat "$work/out")"
}

mix escript.build >/dev/null

# One: the transcript.
mkdir "$work/data"
timeout 300 ./jobq check "$work/data" script/check.script >"$work/raw.txt"
python3 script/normalize.py <"$work/raw.txt" >"$work/out.txt"
diff -u script/expected.txt "$work/out.txt"

# Two: serve, client, compact, and the exit codes.
mkdir "$work/served"
timeout 300 ./jobq serve "$work/served" --port "$port" >"$work/serve.log" 2>&1 &
served=$!

waited=0
until grep -q "serving" "$work/serve.log" 2>/dev/null; do
  waited=$((waited + 1))
  [ "$waited" -gt 100 ] && fail "the service did not come up: $(cat "$work/serve.log")"
  sleep 0.1
done

expect_status 0 ./jobq client 127.0.0.1 "$port" alice POST /jobs \
  '{"queue":"emails","payload":"from check.sh","max_attempts":2}'
expect_body '201 {"id":"j_1"'

expect_status 0 ./jobq client 127.0.0.1 "$port" bob POST /queues/emails/lease '{"lease_ms":60000}'
expect_body '"state":"leased"'
expect_status 0 ./jobq client 127.0.0.1 "$port" bob POST /jobs/j_1/ack
expect_body '"state":"done"'
expect_status 0 ./jobq client 127.0.0.1 "$port" anyone GET /health
expect_body '"done":1'

kill "$served"
served=""
sleep 0.5

# The log the service wrote has one record per change; compaction leaves one
# line per live job, and the service reads its own compacted log.
[ "$(grep -c '' "$work/served/jobq.log")" = "3" ] || fail "expected three records in the log"
expect_status 0 ./jobq compact "$work/served"
expect_body "1 job(s)"
[ "$(grep -c '' "$work/served/jobq.log")" = "1" ] || fail "expected one line after compaction"

expect_status 0 ./jobq check "$work/served" script/check.script
expect_body '< 201 {"id":"j_2"'

# The exit codes: 2 for a usage error, 1 for a directory that cannot be opened,
# a port that cannot be bound, or a service that cannot be reached.
expect_status 2 ./jobq
expect_status 2 ./jobq dance
expect_status 2 ./jobq serve "$work/served" --port seven
expect_status 1 ./jobq compact /proc/self/mem/nope
expect_status 1 ./jobq client 127.0.0.1 "$port" alice GET /health

echo "check.sh: ok"
