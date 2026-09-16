# jobq change 3, Go: report

The store restarts itself, with a restart budget and a chaos switch
(`mo-lang/mo-wiki/spec/programs/01d-job-queue-change-3.md`).

## Result

Every check is green:

- `go vet`
- `staticcheck ./...`
- `go test -count=1 ./...`
- `go test -race -count=1 ./...`
- `jobq/check.sh`

The change is committed as `jobq: change 3` and not pushed.

**Wall-clock:** about 12 minutes (about 710 s), from reading the spec to the
commit.

## How it works

A new `Board` (`jobq/board.go`) sits between the API and the queue. It holds the
live queue and its store.

**When the queue breaks.** The queue marks itself `broken` while it still holds
its lock. Two things cause this:

- a rule the queue itself broke: a never, an invariant or an ensure (not a
  requires);
- a panic while its lock is held. `tx.end` recovers the panic, sets the flag,
  releases the lock and re-panics.

Every later holder of the lock sees the flag and leaves with a 503.

**The restart.** After each request, the API asks the board to check the flag.
If it is set, the board takes itself down: every request gets a 503 until the
restart ends. In the background, the board then:

1. waits for the lock;
2. closes the store, which cuts any torn tail and releases the flock;
3. checks the budget;
4. replays the log into a new queue and starts serving it.

**Chaos.** `--crash-every N` counts every record a commit writes, including the
moves a look makes. After the N-th record is synced, it panics inside the
commit, so it goes through the same path as a real failure.

**Giving up.** When the budget is spent, or a restart itself fails, the board
closes `Done()`. `serve` then shuts HTTP down and exits 70. The store is already
closed and whole, and `jobq verify` exits 0 on the folder.

## Loops to green, by cause

There were 6 failing runs. In every case, the first fix worked.

| #   | Check         | Diagnostic                                                                                                          | Cause                                                                                                                                  | Next edit fixed it?                                                                                           |
| --- | ------------- | ------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| 1   | go vet        | `api_test.go:26: unknown field q in struct literal of type API`                                                     | Tests not yet moved to the new `API{b *Board}`                                                                                         | yes                                                                                                           |
| 2   | go vet        | `board_test.go:119: mismatched types *string and untyped string` (`after.Worker != "w1"`)                           | Bug in my new test: `jobJSON` fields are pointers                                                                                      | yes                                                                                                           |
| 3   | staticcheck   | `board_test.go:271: SA4006 this value of body is never used`                                                        | Bug in my new test                                                                                                                     | yes                                                                                                           |
| 4   | go test -race | `TestHealthNeedsNoToken` and `TestScheduledJobsThroughTheAPI`: health body now has `restarts`                       | Expected, change to the spec'd output                                                                                                  | yes (expectations updated)                                                                                    |
| 4   | go test -race | `TestAPanicCostsOnlyItsOwnRequest`: the process panicked in the restart goroutine (the store panics inside `Close`) | The old test's premise is overruled by this spec (see decision 2). It also showed a real bug: a restart that panics killed the process | yes: the test was replaced, and `restart` now recovers and gives up (new test `TestARestartThatFailsGivesUp`) |
| 4   | go test -race | `TestCheckCommandMatchesExpected`: output differs                                                                   | Expected: `restarts` field and the new `crash` lines in the script                                                                     | yes (`check.expected` regenerated and diffed by hand)                                                         |
| 5   | go vet        | `api_test.go:10: "reflect" imported and not used`                                                                   | Removing the old test left the import unused                                                                                           | yes                                                                                                           |
| 6   | go test       | `TestLeasesSurviveARestart` and `TestChaosUnderLoad`: 503 `the service is restarting`                               | Bug in my tests: they read before the async restart finished                                                                           | yes (tests wait for `waitReady`)                                                                              |

**By cause:**

- Test code I wrote wrong: 4 (runs 2, 3, 5, 6)
- Callers not yet moved to the new API shape: 1 (run 1)
- Expected output changes, plus one real bug found by an old test: 1 (run 4)

The first `-race` run also went past the tool's 120 s foreground limit and was
moved to the background. That was not a failure.

## Files changed

In `experiments/control-run/go/jobq/`:

- `board.go` (new): the supervisor, the budget, the chaos counter, and give-up /
  exit 70.
- `board_test.go` (new) covers:
  - the chaos restart, including a failing look move;
  - leases surviving a restart;
  - a broken rule causing a restart;
  - a panic under the lock causing a restart, with its torn tail cut;
  - a panic outside the queue costing only its own request;
  - the budget: exhaustion, a fresh window, and 0 restarts;
  - a restart that itself fails;
  - a random-failure simulation over 40 seeds;
  - chaos under load over a real socket, with `/health` answering 200 within 1 s
    and data present after a stop and start;
  - `serve` exiting 70, then `verify` on the folder;
  - option parsing.
- `queue.go`: the `broken` flag, `guard`, the chaos hook in `commit`, panic
  recovery in `tx.end`, and `Health.Restarts`.
- `api.go`: the API reads from the board; `/health` reports `restarts`.
- `serve.go`: `openBoard`, `startServiceWith`, `parseServe` with the new
  options, and exit 70.
- `store.go`: `Append` marks the store dirty before writing, so a panic
  mid-write leaves a tail that gets cut.
- `check.go`: new `crash` script step; after each request, the check waits for
  the board to be ready.
- `check.sh`: section 6, which runs chaos, restarts and exit 70 on the served
  process, then `verify`, and checks that `compact` refuses `--crash-every`.
- `main.go`: usage line.
- `api_test.go`: the harness is built on a board over a memory file; health
  expectations updated; the old panic test removed.
- `sim_test.go`: uses a fixed board.
- `testdata/check.script`, `testdata/check.expected`: the `crash` steps and
  `restarts`.

Also changed: `REPORT-change-3.md` (this file).

## Decisions the spec did not cover

1. **What counts as a failure of the board.** Three things do:
   - a never, invariant or ensure violation raised by the queue;
   - any panic while the queue's lock is held;
   - the chaos switch.

   A failed requires stays a 400. A store that refuses writes (`ErrStore`) stays
   a per-request 503 with no restart, as change 2 says. A queue that does not
   answer in time (`ErrBusy`) also stays a per-request 503.

2. **A panic under the queue's lock now restarts the board.** Under change 2 it
   cost only its own request. I read this spec's "an unexpected error while a
   batch is being applied" as overriding that. A panic outside the lock
   (decoding, routing) still costs only its own request.
3. **"The process or thread that holds the board dying" has no Go equivalent.**
   The board is not a separate goroutine that can die alone: a panic in any
   goroutine kills the whole process. The panic-under-lock path stands in for
   it.
4. **The restart runs in the background.** The failing request gets its 503 at
   once; replay happens in a goroutine, and requests get 503
   `the service is restarting` until it ends.
5. **Queue-lock holders already waiting when the failure happens are
   answered 503.** They see the `broken` flag; they are neither served from
   stale memory nor kept waiting.
6. **Where the chaos failure fires.** It fires after the whole commit's records
   are synced and before they are applied to memory. So memory differs from the
   log until the restart rebuilds it, which is what the restart path must
   survive.
7. **Chaos counts records, not commits.** A commit that carries look moves plus
   its own change counts as several writes. The counter crosses a multiple of N
   at most once per commit, so one commit causes at most one failure. The count
   carries across restarts, and replayed records do not count.
8. **How the budget is counted.** When a failure happens, the board counts the
   earlier restarts newer than `window`. If there are already `max_restarts` of
   them, it gives up; otherwise it restarts. With `--max-restarts 0`, the first
   failure exits 70.
9. **Which clock the window uses.** The restart window is measured on the
   service's clock: the real clock in `serve`, the manual clock in tests.
10. **Option ranges and order:**
    - `--max-restarts` is 0 to 1,000,000.
    - `--restart-window` is 1 to 86,400 whole seconds.
    - `--crash-every` is any whole number, 0 for never.
    - Options can come in any order after `<dir>`, each at most once.
      Non-canonical numbers such as `05` are usage errors (exit 2), as with
      `--port`.
11. **`uptime_ms` keeps counting from process start across a board restart.**
    The restart is not a new process. A stop and start still resets it, as
    before.
12. **A restart that itself fails gives up.** This covers the store failing to
    close, the log failing to replay, or a panic during the restart. The service
    exits 70 rather than retrying, because a log that cannot be reopened will
    not get better by trying again.
13. **Exit 70 writes nothing more.** The store is closed (torn tail cut) before
    the budget is checked. After giving up, every request is answered 503 until
    HTTP shutdown finishes; then the process exits.
14. **`Store.Append` marks the store dirty before the write, not only after a
    failed one.** A panic inside the write therefore still has its partial tail
    cut when the store is closed.
15. **The `crash` step in the check script.** `jobq check` gets a `crash` step
    (the implementation's own hook) that fails the next write the board applies.
    After every request, the check waits until the board is serving again, so
    its output is deterministic.
16. **The 503 body for a failure the chaos switch or a panic caused** is the
    existing `{"error":"the request could not be completed"}`. A request that
    arrives during the restart gets `{"error":"the service is restarting"}`.
