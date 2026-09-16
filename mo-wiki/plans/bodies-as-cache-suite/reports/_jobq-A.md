# jobq regenerated — report

Every function body in `examples/programs/jobq/` was written again from the modules' intents,
types, signatures, contracts and tests, and from `mo-wiki/spec/programs/01-job-queue.md`. The
tests were not touched. Ten modules, 2,135 lines stripped to signatures, now 3,114 lines.

## Done-when

- **Wall-clock: 26 minutes 19 seconds** (01:15:13 to 01:41:32 UTC, 16 Sep 2026), from the first
  read of `examples/README.md` to the last green run.
- `mo check` clean on all ten modules; `mo check --recipe Recipes.Store.Store store.mo` matches
  11 signatures and passes the recipe's 8 tests.
- `mo test` green on all ten: 55 tests, 4 properties over 200 seeds each, 0 failed, 0 skipped.
- `mo test --sim 100` green; `queue.mo` holds 3 of 3 tests under faults, `server.mo` 2 of 2 under
  its `# sim: --faults 20 --until 0.5` line (re-run at 400 seeds to check it is not flaky).
- All five `# run:` lines byte-identical to their `.expected` files, with the expected exit codes
  (0, 0, 2, 1, 1). `data/demo/jobq.log` and `data/compact/jobq.log` are unchanged by the runs.
- `mo fmt --check` clean on all ten.
- `mo test --write --sim 100` has rewritten every `verified:` line; the `.mo.ids` sidecar's
  changes are confined to the ten `jobq/` entries.
- Every `mo` process ran under `timeout 120` with a 4 GiB watchdog; the watchdog never fired (the
  slowest single command was `mo run -- check`, 1.3 s).

## Loops to green, by cause

Five failures after an edit of mine. **Every one was fixed by the next edit.**

| # | Module | Cause | Diagnostic / test | Fixed first try |
|---|---|---|---|---|
| 1 | `board.mo` | `return board` written as a `case` arm's expression in `unindexed` | MO0102 | yes |
| 2 | `books.mo` | a boolean expression wrapped onto a second line as a `case` arm's value in `held_twice?` | MO0102 | yes |
| 3 | `moves.mo` | `with_jobs` folded with `reduce`, so the anonymous function captured `fs` | MO0409 | yes |
| 4 | `server.mo` | `Time.fixture()` in `unknown()`, a function outside a test | MO0403 | yes |
| 5 | `server.mo` | the fault test failed under `--sim 100 --faults 20 --until 0.5`, seed 6243096878674939956: `assert turn(...) == ""`, left `"a 503 changed the jobs"` | test, not a diagnostic | yes |

Loop 5 is the only one that was a thinking mistake rather than a syntax one. `turn` read the jobs
before a request as `snapshot(service) or []`, so a snapshot the faults had already knocked out
read as *no jobs at all*, and the next 503 looked like a change. A turn that cannot see the jobs
beforehand has no evidence, so it now says nothing (`turn` matches on the `Option` and a new
helper `took` does the lease).

Not counted as loops, since they were the state the strip left behind rather than my edits: three
signatures whose continuation line had been eaten with the body (`Board.with_number`'s
`Map(K, Set(UInt64)))`, `Journal.put_all`'s `StoreError)`, `Main.ran`'s `Problem)`, all MO0103),
and the two empty `fn update` bodies (MO0101, "expected `case`"). `Journal.put_all`'s `requires`
went with its signature line; it was put back as
`requires pairs.all?(fn(pair) key?(pair.0) and value?(pair.1) end)`, which is what its
`test rejects "a put of many with a key holding a space"` trips.

Two more diagnostics came from a throwaway probe file, not from the program: MO0101 (an
assignment as a `case` arm's expression) and MO0403 (`a capability is passed down as a parameter,
never returned`). The second decided how the crowd of 1,200 connections is held — see decision 12.

No run ever printed the wrong bytes: all five `# run:` lines matched their `.expected` file the
first time they were run.

## Decisions the spec did not cover

1. **How a replay knows which ids were handed out.** The spec says a job's id is `j_` and "a
   counter that never repeats, per service", but not how a restart learns the counter. The log
   carries a record of its own under the key `ids`, and ids are reserved a thousand at a time: a
   create whose `next_id` has reached the reserved ceiling writes `SET ids <next_id + 1000>` in
   the *same append* as the job's record, so a replay resumes above every id ever handed out —
   including one whose job was deleted and one whose write failed. `data/demo`'s `SET ids 1000`
   is what makes the first job the check creates `j_1000`.

2. **An id is spent before its record is durable.** `Moves.creating` raises `next_id` on the books
   it hands to `Books.committed`, not on the books `committed` gives back, so a create answered
   `503` still burns its id. Without this a torn write could hand the same id to two jobs, which
   is what "a job is never held by two workers at once" turns into once the log is replayed.

3. **A lease's place in the index is a whole second.** `Board.due` buckets each queue's leased
   jobs by the second its lease runs out (whole seconds since 2000, an `Int64`). A look gathers
   every bucket at or below the current second and *then* filters on the exact millisecond
   deadline, so the index is coarse and the answer is not. The spec only asked that a lease be "a
   deadline, not a timer".

4. **Which looks expire a lease, and how far each one looks.** The spec names "a lease request, an
   ack, a fail, a read, or the listener's `Idle`". Read here means both `GET /jobs/{id}`, which
   looks at its own job, and `GET /jobs`, which looks at its queue's leases when `queue=` is given
   and at every queue's when it is not. `DELETE` looks too, so it does not answer `409` on a lease
   that has already run out, and so does a refused ack or fail. Every expiry a look finds goes
   into the same append as the change the call makes, so a look costs at most one write.

5. **Every response's error sentence.** The spec gives statuses, not words. All of them are the
   program's own and `jobq.expected` pins them: `a request needs authorization: Bearer <token>`,
   `no such job`, `no route <path>`, `this route takes GET, DELETE`, `the job is leased`, `the
   caller does not hold a live lease on the job`, `queue must be 1 to 64 letters, digits, - and
   _`, `max_attempts must be a whole number from 1 to 100`, `lease_ms must be a whole number from
   100 to 3600000`, `state must be queued, leased, done, or dead`, `the body is not JSON`.

6. **The listener's `idle:` is 5 seconds**, against an acceptor mailbox of 4,096. The runtime
   counts a connection that has sent no whole request against that bound, so 1,200 silent clients
   leave 2,896 of headroom; `idle:` is what frees them, and 5 seconds is short enough that a crowd
   cannot accumulate and long enough that a real client on a local socket is never cut off. The
   acceptor's `Idle` is turned into a `Sweep` ask that waits 10 seconds, which bounds every file
   call the sweep makes; `Idle` only arrives when no client came for 5 seconds, so nothing is
   waiting on that ask.

7. **`jobq check` and its own log.** `jobq.check.log` is removed *before* the service opens and
   again after the script, and `Store.writing_to` resets the replayed line count and the
   cut-short flag along with the name and size. So `data/demo`'s `jobq.log`, whose last line is
   cut short, is replayed but never written to, and the check's own log does not start life
   needing a rewrite. `Books.opened` replays the folder's `jobq.log` first and then continues
   over `place.log` when the two differ.

8. **A hand-edited log cannot crash the service.** `Job.job_of` refuses a record whose state is
   `queued` and whose `attempts` have already reached `max_attempts` — a state no move of the
   program can reach, since a fail or an expiry on the last attempt is `dead`. Without the refusal
   such a record would reach `Job.leased`, whose `requires job.attempts < job.max_attempts` would
   crash the queue process rather than refuse the line.

9. **What a sweep answers.** `Moves.swept` hands back the jobs whose leases it ended as a `Listed`
   outcome, and `Jobq.Queue` turns that into the count its `Sweep` message replies with. The spec
   asks for the sweep, not for its answer.

10. **A job is written by hand, the health counts by `Json.encode`.** `Job.shown` is written out
    field by field, as the module's comment says it must be; `Api.health` is `Json.encode` of the
    `Health` struct, whose field order already is the spec's (`queued, leased, done, dead,
    uptime_ms`).

11. **`compact` cannot say why a folder would not open.** `Jobq.Main`'s `use Jobq.Store{...}` line
    does not import `StoreError`, so `jobq compact` reports any failure to open as `is not a
    folder jobq can read`. Adding `StoreError` to that `use` line would have meant editing a
    module header the strip left intact, which this run did not do.

12. **The crowd holds its connections by recursion.** A capability cannot be returned from a
    function (MO0403), so a `List(Conn)` of 1,200 silent clients was not available. `Main.crowded`
    opens one connection, plays *the rest of the script inside that frame*, and closes it on the
    way out, so all 1,200 are open while the producer's request is answered. 1,200 frames plus the
    script's 43 is well under the 10,000-call depth limit. The count that could not be opened goes
    to stderr, since the system's descriptor limit decides it; on this VM all 1,200 opened.

13. **Six private helpers beyond the stripped signatures**, each named in its module:
    `Queue.counted` (a `Sweep`'s count out of an outcome), `Server.ended_by` (the `Idle` ask),
    `Server.tried` (a job's number and attempts, what a `503` must not have changed),
    `Server.took` (the lease half of a turn), `Main.trip_query` (what a path holds after its `?`)
    and `Main.crowded`.

14. **What a `503` is allowed to have changed.** The fault test compares each job's
    `(number, attempts)` before and after, not the jobs themselves: a lease that runs out between
    the two looks is a legitimate change that leaves `attempts` alone, while a lease that landed
    without its answer arriving does not. So the test asserts exactly the thing the never is
    about, and not the clock.

## Contracts the reader expects to see

The `requires` the spec asks for are on `Job.job` (queue name, payload, max_attempts) and
`Job.leased` (lease_ms), each with its `test rejects`; `Store.put` and `Journal.put_all` carry the
store's. `Moves.leasing` has `ensures result.outcome is Handed(job) implies handed_to?(books, job,
worker)` — leased to the caller with `attempts` one higher — and `Moves.acking` has `ensures
result.outcome is Found(job) implies job.state == Done`.

**Invariants left out of `process Service`, and why.** The process as the spec left it declares
none, and none could be added that a message can break:

- *the id counter never goes backwards* — `state.books.next_id` is only ever set from
  `Books.next_id`, which `creating` raises by one and `opened` raises to the log's ceiling. No
  message lowers it, so no test could trip it. It is documentation.
- *a job's attempts never exceed its max_attempts* — already a `never` in `Jobq.Job` over every
  `Job` value the run holds, which is stronger than an invariant over one process's state, and
  `leased`'s `requires` refuses the only move that could break it.
- *no job is held by two workers at once* — already a `never` in `Jobq.Books`, over the `Step`s of
  every write, which covers the writes a restart replays as well as the ones this process made.
- *the store is open before a job is served* — `readied` opens it at the first message after a
  start or a restart and `served_by` answers `503` when it cannot, so no message can leave a call
  served against an unopened store.

The four `never`s in `Jobq.Books` are checked over the `Step`s a write makes. A call that looks at
a job and changes nothing makes no `Step`, so *a lease that ran out blocks its job past a look*
holds vacuously; it is the expiry written into every look's append that actually keeps it, not the
`never`.

## Deadlines: the `within:` count

31 `within:` sites; 4 of them are in test helpers (`Moves.with_jobs`, `Queue.ask`, `Queue.got`,
`Server.sent`). Of the 27 in the program:

- **7 derive from an enclosing deadline.** All are in `Jobq.Journal`: five pass a caller's
  `Deadline` straight through (`list`, `size`, `fold_lines`, a compaction's `rename`, an append's
  size check), and two tighten it with `at_most` by a number chosen for that call — 5 s for an
  append, so a failed one can still be looked at, and 20 s for a compaction's write, so the rename
  has time left. The chain above them is derived too: the worker asks the service within 60 s, and
  `reply_by` inside the update is what remains of that one ask, so nothing the service does for a
  request outlives the request.
- **20 are numbers chosen for the call**, because there is no enclosing deadline to derive from.
  13 are in `Jobq.Store`, whose recipe functions keep their own deadlines for `main` and for the
  recipe's tests (5 s append and size, 20 s + 5 s compaction, 600 s replay, 10 s list and stat).
  7 are in `Jobq.Main` and `Jobq.Server`, where `main` has no asker and the acceptor's `Idle`
  carries no reply: 21 minutes for the opening replay, 5 s to bind a listener, 10 s for the
  one-shot client and for the script and check-log housekeeping, 30 s for `exchange.reply`, 60 s
  for the worker's ask, 10 s for the `Idle` sweep.

So one number — the worker's 60 seconds — is the root of every deadline a request's work runs on,
and the store's own numbers are the root of the rest.

## Questions for a running service the runtime could have answered

Kept for directions 37 to 40, from what was actually wanted while getting this green:

1. Which process holds the books right now, and whether `state.opened` is true — the "folder
   cannot be read" path was reasoned about rather than looked at.
2. What a service's `next_id` and `reserved` are between two updates, to see the `SET ids` line
   land without reading the log.
3. The last ten messages the queue process took, to tell a `503` from a timed-out ask apart from a
   `503` from a refused write — the distinction loop 5 turned on.
4. How many connections the acceptor's mailbox is holding, and how many of them have sent nothing,
   during `crowd 1200`.
5. The slowest update of a check run, to see whether the crowd or the replay dominates.
