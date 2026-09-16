# jobq, change 2: the maintainer's report

The change at `mo-wiki/spec/programs/01c-job-queue-change-2.md` made to
`examples/programs/jobq/`: the folder is checked at open, a failing request
never takes the service down, and operators get `GET /queues`.

## Wall-clock

18 minutes 9 seconds, from reading the change page to the last green run.

## Loops to green, by cause

Eight checks or tests failed, plus one recurring bookkeeping refusal. Every fix
worked the first time.

| #   | cause                                 | the diagnostic or the failing test                                                                                                                               | the fix                                                                                                                                                                                                                                                                       | first fix worked       |
| --- | ------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------- |
| 0   | bookkeeping, recurring                | `MO0317 ... changed since mo test --write recorded the verified: line` after every edit, and again in each dependent module once `board.mo` and `api.mo` changed | `mo test --write` per file, and at the end once more in dependency order (job, store, board, api, queue, server, main)                                                                                                                                                        | yes                    |
| 1   | my test's wrong assumption            | `board.mo`: `assert ill_formed(ill) == Some(("j_2", "a leased job has at least one try"))` failed, left `None`                                                   | the lease hands out the oldest job, so `j_1` is the leased one; the ill record and the expectation moved to `j_1`, and the "first key in order" case became a separate `j_0` record                                                                                           | yes                    |
| 2   | exhaustiveness                        | `MO0308 this case does not cover Tallied(_)` at four `case`s in `queue.mo`                                                                                       | an arm for `Tallied(_)` in each                                                                                                                                                                                                                                               | yes, and it ran into 3 |
| 3   | column limit                          | `MO0104 expected a pattern` where the new arm was wrapped after `\|`                                                                                             | see 4                                                                                                                                                                                                                                                                         | —                      |
| 4   | no catch-all                          | `MO0309 the _ arm hides Made(_), ...` where `_` replaced the wrapped pattern                                                                                     | two helpers written without a `case` over `Outcome` (`gone?` as `!(x is Found(_))`, `aged_log` and `ended` as `if x is Found(held)` with the rest falling through); recorded as finding 4 in `TOOLCHAIN-BUGS.md`                                                              | yes                    |
| 5   | statement in an arm                   | `MO0102 a case arm holds one expression after its :; return is a statement`                                                                                      | the arm's body extracted as `aged_text`                                                                                                                                                                                                                                       | yes                    |
| 6   | my test's wrong premise               | `server.mo`: `assert in?(sent(http, port, GET /health), [200])` failed with a store on `Fs.fixture(delay: 1.minute)`                                             | a slow store blocks the queue, so the reads time out too; an unwritable store is not a slow one. The test now serves a store whose folder lies outside its `Fs`, where every write is refused at once and reads are untouched                                                 | yes                    |
| 7   | the new check refusing an old fixture | `main.mo`: `assert opened_store(fs, err, "d") is Ok(table)` in the cut-short test, whose log held `SET a 1`                                                      | the cut-short test's log now holds real job records, and the folder check has tests of its own                                                                                                                                                                                | yes                    |
| 8   | the real folder, by hand              | `chmod 555` on the served folder did not refuse an append to a log that already exists                                                                           | the operator's case is the log itself unwritable: with `chmod 444 jobq.log` a create is `503 {"error": "the log did not take the change"}`, a read is `200`, `/health` does not move, and the next create after `chmod 644` is `201` with its record on disk, with no restart | yes                    |

## What is green

- `mo test` on all seven modules: job 27, store 12, board 17, api 9, main 9,
  queue 8 (`--sim 100`), server 6 (`--sim 100`); server's six all hold under
  faults.
- `mo check programs/jobq/store.mo`: the store recipe, 11 signatures and its 8
  tests.
- All seven `# run:` lines against their `.expected` files and exit codes, under
  `mo run`.
- `mo build --tests` for each module and `mo build` for the program: every
  binary prints exactly what the interpreter prints and exits as it exits,
  `check` over real sockets included.
- By hand over a real socket: create, `/queues`, the read-only log above, and
  recovery.

Two things were already this way at `HEAD` and are unchanged by this work:
`queue.mo`'s "a scheduled job is queued once the clock passes its run_at" holds
only without faults (1 of 6 under `--sim`, at HEAD too, under its own seeds),
and `mo fmt --check` differs on api, board, job, main, and server (at HEAD too);
the new code was kept inside the 100-column limit where the formatter's other
differences did not already stand.

## Files changed

| file                                                        | what                                                                                                                                                                                                                                 |
| ----------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `examples/programs/jobq/job.mo`                             | `rule_broken(key, record)`, the well-formedness rule as one `requires`-free function, with `tries_broken`; two tests, one per state and one for the records that are not jobs                                                        |
| `examples/programs/jobq/board.mo`                           | `Tally`, `tallies`, the `Tallying` command and the `Tallied` outcome; `ill_formed` over a store's entries, with `ids_broken`; `leasable?`, the guard that answers 503 where a contract would crash the queue; two tests              |
| `examples/programs/jobq/api.mo`                             | the `/queues` route and its 405/401, `Tallied` as `200 {"queues": [...]}`, `tally`; one test                                                                                                                                         |
| `examples/programs/jobq/queue.mo`                           | `Want` is an ask whose `Reply(Outcome)` the queue keeps until the batch is on disk; `answer_of`, the worker's five-second deadline, `Timeout` and `Down` as 503; the worker has no `Done`; one test for a log that cannot be written |
| `examples/programs/jobq/server.mo`                          | `Go` without the worker's own handle, `started_on` and `unwritable()`; two tests, the unwritable store over the wire and `/queues` over the wire                                                                                     |
| `examples/programs/jobq/main.mo`                            | `jobq verify <dir>`, the `Ill` problem and its line, `whole`, the folder check in `opened_store` so serve, compact, verify, and check all refuse alike; `counted`, verify's line; two `# run:` lines; two tests                      |
| `examples/programs/jobq/data/session.txt`                   | `p GET /queues` before and after the delete that empties `later`, and `- GET /queues`                                                                                                                                                |
| `examples/programs/jobq/data/ill/jobq.log`                  | new: a folder whose one record is a queued job with no tries left                                                                                                                                                                    |
| `examples/programs/jobq/jobq.expected`                      | the check transcript, with the three new lines                                                                                                                                                                                       |
| `examples/programs/jobq/jobq-6.expected`, `jobq-7.expected` | new: `verify data/demo` and `verify data/ill`                                                                                                                                                                                        |
| `examples/programs/.mo.ids`                                 | the sidecar, from `mo test --write`                                                                                                                                                                                                  |
| `examples/README.md`                                        | the jobq entry, which still named the module list from before change 1                                                                                                                                                               |
| `examples/programs/jobq/TOOLCHAIN-BUGS.md`                  | finding 4: an or-pattern too long for the column limit has nowhere to go                                                                                                                                                             |
| `REPORT-change-2.md`                                        | this file                                                                                                                                                                                                                            |

## Decisions the spec did not cover

1. **"The first such record" is the first key in byte order.** The store keeps
   its keys in 256 buckets with no order of their own, so `ill_formed` sorts the
   entries by key and reports the first that breaks a rule. `ids` sorts before
   every `j_`.
2. **Each rule is a phrase that finishes the line.**
   `jobq: <dir>: record <key>: <rule>` reads
   `record j_1: a queued job has tries below its max_tries`,
   `record j_7: its id is j_2, not its key`, `record j_9: is not a job`,
   `record ids: is not a number`, `record ids: the next id is below j_3`.
3. **`ids` lower than a job's number is read literally.** The counter is refused
   when it is below the highest job's number; equal is allowed, since the
   counter names the next id to hand out.
4. **The check lives in one place.** `Jobq.Board.ill_formed` over the store's
   entries, called from `main`'s `opened_store`, so `serve`, `compact`,
   `verify`, and `check` refuse the same folder with the same line and no
   command can be added that skips it.
5. **`verify` never writes.** It opens through `fs.read_only`, so it does not do
   the whole-log rewrite `serve` does for a log whose last line was cut short;
   the cut-short line is still one sentence on stderr, and the folder still
   verifies.
6. **Verify's numbers come from the replayed board.** The five counts are
   `/health`'s without `uptime_ms`, `<n>` is their sum, and `next id` is the id
   the next create would take, not the reserved counter the log holds.
7. **The five-second rule is the worker's, not the queue's.** The worker asks
   the queue with `within: 5_000.ms`, so a queue that is slow, stuck, or down
   costs the request that asked and no other. The queue keeps no timer of its
   own.
8. **The mechanism for that is the reply the queue keeps.** `Want` became an ask
   whose `Reply(Outcome)` goes into the queue's state and is answered by the
   flush (design-v0/03, session 8, step 31), in place of `send(Want)` and a
   `Done` message back. The spec asked for the behaviour; this is the only shape
   in the language that gives one deadline per caller, `Down` when the queue has
   crashed, and one fsync per batch all at once.
9. **A batch is still all or nothing.** A read that shares a batch with a write
   the log refused is answered 503 with it. A batch of reads alone is never
   refused, which is what the spec's "keeps answering reads" describes and what
   the hidden suite's `2xx`, `4xx`, or `503` allows.
10. **`/queues` counts are summed from the jobs at each request** rather than
    kept incrementally, so they cannot drift from `/health`'s totals, which is
    the property the page asks for. The cost is one pass over the jobs per
    `/queues` request, as a listing already costs.
11. **A lease the job's contract would refuse is answered 503,** not crashed on:
    `leasable?` guards what `leased` requires. The folder check is what keeps
    such a record out; this is the second lock, for "anything the implementation
    did not expect".
12. **Making a store unwritable in a test.** No fixture turns a folder read-only
    part way through a run, and a read-only `Fs` cannot be handed to the queue
    (the checker follows it into a process). So the wire test serves a store
    whose folder lies outside its `Fs`, where every write is refused at once and
    reads are untouched, and the recovery half is at `flushed`, where the batch
    after the refused one is handed a store that can be written. The operator's
    real case was run by hand over a socket, loop 8 above.
13. **Exit codes keep the shapes already there.** A folder that cannot be opened
    at all is exit 1 with its old wording, an ill-formed record is exit 1 with
    the new line, and a usage error (`verify` with no folder, or with two) is
    exit 2.
14. **The check script gained what it can say.** `p GET /queues` before and
    after the delete that empties the `later` queue, and `- GET /queues` for the
    401; `verify` is a `# run:` line, since the script speaks only HTTP.
15. **`data/ill` is a new fixture folder** holding one done job and one queued
    job with no tries left, so run 7 refuses a folder whose other record is
    fine.
