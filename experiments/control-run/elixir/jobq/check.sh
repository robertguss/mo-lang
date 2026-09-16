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
#
# Three: a folder the version before change 1 served, from
# test/fixtures/round7, opened and compacted with no tool and no old name
# left in the log.
#
# Four: the folder checked at the door — `verify` on the folders the run
# wrote, and a hand-written record in a state the API could never produce
# refused by serve, compact, and verify alike.
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

# What a refusal says, which the commands write to stderr.
expect_error() {
  grep -q -- "$1" "$work/err" || fail "expected '$1' in: $(cat "$work/err")"
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
  '{"queue":"emails","payload":"from check.sh","max_tries":2}'
expect_body '201 {"id":"j_1"'

expect_status 0 ./jobq client 127.0.0.1 "$port" bob POST /queues/emails/lease '{"lease_ms":60000}'
expect_body '"state":"leased"'
expect_status 0 ./jobq client 127.0.0.1 "$port" bob POST /jobs/j_1/ack
expect_body '"state":"done"'
expect_status 0 ./jobq client 127.0.0.1 "$port" anyone GET /health
expect_body '"done":1'
expect_status 0 ./jobq client 127.0.0.1 "$port" anyone GET /queues
expect_body '{"name":"emails","queued":0,"scheduled":0,"leased":0,"done":1,"dead":0}'

# A job with a delay waits in scheduled, and nothing leases it; a retry of a
# job that is not dead is refused.
expect_status 0 ./jobq client 127.0.0.1 "$port" alice POST /jobs \
  '{"queue":"digests","payload":"tomorrow","max_tries":1,"delay_ms":3600000,"backoff_ms":1000}'
expect_body '"id":"j_2"'
expect_body '"state":"scheduled"'
expect_status 0 ./jobq client 127.0.0.1 "$port" dave POST /queues/digests/lease
expect_status 0 ./jobq client 127.0.0.1 "$port" alice POST /jobs/j_1/retry
expect_body '"error":"job is not dead"'
expect_status 0 ./jobq client 127.0.0.1 "$port" anyone GET /health
expect_body '"scheduled":1'
expect_status 0 ./jobq client 127.0.0.1 "$port" anyone GET /queues
expect_body '{"name":"digests","queued":0,"scheduled":1,"leased":0,"done":0,"dead":0}'

kill "$served"
served=""
sleep 0.5

# The log the service wrote has one record per change; compaction leaves one
# line per live job, and the service reads its own compacted log.
[ "$(grep -c '' "$work/served/jobq.log")" = "4" ] || fail "expected four records in the log"
grep -q '"max_tries"' "$work/served/jobq.log" || fail "the log does not use the new names"
! grep -q 'attempts' "$work/served/jobq.log" || fail "the log still uses an old name"
expect_status 0 ./jobq compact "$work/served"
expect_body "2 job(s)"
[ "$(grep -c '' "$work/served/jobq.log")" = "2" ] || fail "expected two lines after compaction"

# `verify` reads the same folder without serving it.
expect_status 0 ./jobq verify "$work/served"
expect_body "2 jobs: queued 0, scheduled 1, leased 0, done 1, dead 0; next id j_3"

expect_status 0 ./jobq check "$work/served" script/check.script
expect_body '< 201 {"id":"j_3"'

# Three: a folder the version before this change served. It opens with no
# tool: the leases that ran out are read by the rules of the change, and a
# compaction leaves no old name behind.
cp -R test/fixtures/round7/data "$work/round7"
grep -q '"max_attempts"' "$work/round7/jobq.log" || fail "the fixture is not in the old shape"

expect_status 0 ./jobq compact "$work/round7"
expect_body "5 job(s)"
! grep -q 'attempts' "$work/round7/jobq.log" || fail "compaction left an old name behind"
grep -q '"backoff_ms":0' "$work/round7/jobq.log" || fail "compaction did not write a backoff"

expect_status 0 ./jobq verify "$work/round7"
expect_body "5 jobs: queued 1, scheduled 0, leased 2, done 1, dead 1; next id j_7"

expect_status 0 ./jobq check "$work/round7" script/check.script
expect_body '< 201 {"id":"j_7"'

# Four: the folder checked at the door.
# A record in a state the API can never produce: a leased job with no worker.
mkdir "$work/ill"
{
  printf '%s' '{"id":"j_1","queue":"emails","state":"queued","payload":"hi","tries":0,'
  printf '%s\n' '"max_tries":3,"backoff_ms":0,"created_at":1789000000000,"updated_at":1789000000000}'
  printf '%s' '{"id":"j_2","queue":"emails","state":"leased","payload":"held","tries":1,'
  printf '%s\n' '"max_tries":3,"backoff_ms":0,"created_at":1789000000000,"updated_at":1789000000000}'
} >"$work/ill/jobq.log"

expect_status 1 ./jobq verify "$work/ill"
expect_error "record j_2: a leased job has a worker and a lease_until"
expect_status 1 ./jobq serve "$work/ill" --port "$port"
expect_error "record j_2:"
expect_status 1 ./jobq compact "$work/ill"
expect_error "record j_2:"
[ "$(grep -c '' "$work/ill/jobq.log")" = "2" ] || fail "the refused folder was rewritten"

# A torn last line is still cut off rather than refused.
cp "$work/ill/jobq.log" "$work/ill/torn"
head -1 "$work/ill/jobq.log" >"$work/ill/jobq.log.new"
printf '%s' '{"id":"j_3","queue":"ema' >>"$work/ill/jobq.log.new"
mv "$work/ill/jobq.log.new" "$work/ill/jobq.log"
rm "$work/ill/torn"
expect_status 0 ./jobq verify "$work/ill"
expect_body "1 jobs: queued 1, scheduled 0, leased 0, done 0, dead 0; next id j_2"

# The exit codes: 2 for a usage error, 1 for a directory that cannot be opened,
# a port that cannot be bound, or a service that cannot be reached.
expect_status 2 ./jobq
expect_status 2 ./jobq dance
expect_status 2 ./jobq serve "$work/served" --port seven
expect_status 2 ./jobq verify
expect_status 1 ./jobq verify /proc/self/mem/nope
expect_status 1 ./jobq compact /proc/self/mem/nope
expect_status 1 ./jobq client 127.0.0.1 "$port" alice GET /health

echo "check.sh: ok"
