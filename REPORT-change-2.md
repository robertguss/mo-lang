# jobq, change 2: the report

The change of `mo-wiki/spec/programs/01c-job-queue-change-2.md` made to the Go
program in `experiments/control-run/go/jobq`: the folder is checked at open,
a failing request never takes the service down, and `GET /queues` lists every
queue with its counts.

## Wall-clock

About 12 minutes from reading the spec to the green commit: 10 minutes to the
last failing check, 2 more for the report. Every server and test process ran
under `timeout`; nothing came near 4 GB.

## Loops to green, by cause

Five loops, six distinct causes. Every first fix worked.

1. **Two store tests asserted the old read behaviour.** `TestScheduledMoveIsUndoneWhenTheStoreFails`
   and `TestNothingChangesWhenTheStoreFails` expected `Get` to return `ErrStore`
   when the look's move could not be written. Change 2 says a store that cannot
   be written keeps answering reads, so both now assert the read is answered and
   the job is in the state it was in before the move. Fixed first try.
2. **`TestInvariantsTripThroughStoreRecords` read the old message.** Its
   hand-written records are exactly the ill-formed ones, and `wellFormed` now
   refuses them at open before the invariants run, so the error text changed.
   Rewritten as `TestIllFormedRecordsRefuseTheFolder`, asserting
   `<dir>: record j_1: <rule>` and covering three more rules. Fixed first try.
3. **The simulation's model of a read.** Under faults a `GET /jobs/<id>` now
   answers with the state before the look's undone moves, while the model gave
   the state after them. The model accepts either while faults are on, and the
   check stays strict once they stop. Fixed first try.
4. **Build: `ptr` redeclared.** `verify_test.go` defined a helper `job_test.go`
   already has as a generic. Removed. Fixed first try.
5. **Build: `h.do` called with five arguments.** A stray `""` in the read-only
   folder test. Removed. Fixed first try.
6. **Two wrong expectations in my own new tests.** `DELETE /jobs/j_1` during the
   unwritable-store run answered 409, not 503, because that job was leased: the
   test now deletes a queued job. And `check.sh` expected a queue named `later`
   in the `testdata/v1` folder's `/queues`, which holds `push`. Both fixed first
   try.

Green at the end: `gofmt -l` (clean), `go vet ./...`, `staticcheck ./...`,
`go test ./...`, `go test -race ./...`, `jobq/check.sh`, `logstat/check.sh`.

## Files changed

New:

- `jobq/verify.go` — `wellFormed`, the `illFormed` error, `asIllFormed`, `cmdVerify`.
- `jobq/verify_test.go` — a test per state for `wellFormed`, the key rule, the
  `verify` command on the fixture folders, and serve/compact/check refusing the
  ill-formed one.
- `jobq/testdata/ill/jobq.log` — a hand-written folder: a good record, then a
  leased job with no worker.

Changed:

- `jobq/queue.go` — `wellFormed` on every replayed put; `tx.commitReads`, the
  commit a read makes; `QueueCounts` and `Queue.Queues`.
- `jobq/api.go` — `respond` split out of `ServeHTTP` so a panic is one 503;
  `GET /queues`; an unexpected error is 503, not 500.
- `jobq/serve.go`, `jobq/store.go` — `openQueue` names the folder in front of a
  refused record, and `Compact` goes through it.
- `jobq/main.go` — the `verify` command and the usage line.
- `jobq/check.sh`, `jobq/testdata/check.script`, `jobq/testdata/check.expected` —
  `/queues` after creates and after a delete that empties a queue, `verify` on
  the folders the run leaves behind, and serve/compact/verify all refusing
  `testdata/ill`.
- `jobq/api_test.go` — `/queues` with the sums against `/health`, the unwritable
  store (write 503, read 200, recover, write 2xx), a panic costing one request,
  and a real read-only folder.
- `jobq/queue_test.go`, `jobq/sim_test.go`, `jobq/main_test.go` — as above.

## Decisions the spec did not cover

1. **What a record's key is.** The store is an append-only log, not a folder of
   files, so a put record's key is the job id it carries. "The record's key
   naming the job's id" is checked as `key == job.id` and the refusal prints
   that id: `record j_2: ...`.
2. **Which check runs first.** `wellFormed` runs before the nevers and the
   invariants on replay, so an ill-formed record is always reported as
   `record <key>: <rule>` and never as a contract violation.
3. **Rules folded in beyond the table.** `created_at <= updated_at`, a scheduled
   job's `run_at` after its `updated_at`, a leased job's worker being a valid
   token, and `reason`'s field rule are part of `wellFormed` so every refusal
   speaks in one voice. All four were already refused at open as invariants.
4. **Reads while the store refuses writes.** A read's look still ends run-out
   leases and queues due jobs; when that write fails the moves are undone and
   the read is answered from the state before them, and the next look makes them
   again. The alternative — answering a move that is not on disk — would break
   "memory equals a replay of the durable records".
5. **The default status for an unexpected error is now 503, not 500.** The spec
   says anything the implementation did not expect is a failure in the service.
   Nothing in the program returns 500 any more.
6. **Where a panic is caught, and what it says.** At the HTTP layer, after the
   queue's own `defer`s have released the lock and undone the moves, so the next
   request is answered normally. The body is a fixed
   `{"error":"the request could not be completed"}`; the panic value is not
   handed to the caller.
7. **`verify` takes the same exclusive lock as `serve`**, so it cannot be run
   against a folder a live service holds, and, like `compact`, it creates an
   empty `jobq.log` in a folder that has none rather than refusing.
8. **`verify`'s counts are the states as replayed**, before any lease-expiry
   look: a leased job whose `lease_until` has passed is still counted leased.
   Its `next id` is the counter after replay.
9. **`GET /queues` needs a token** ("with a token like every route") and answers
   `{"queues":[]}` for a service with no jobs.
10. **A real read-only folder cannot force the 503 here.** On macOS a write
    through an already-open descriptor still reaches the disk, so `chmod 0500`
    on the folder does not make the log unwritable. The strict sequence (write
    503, read 200, writable again, write 2xx) is tested through the injected
    `File`; the `chmod` test asserts the spec's list of allowed answers, that a
    503 moves no count, and that writes work afterwards with no restart.
11. **`verify` prints `1 jobs`, not `1 job`** — the line is taken from the spec
    literally, with no plural rule.
