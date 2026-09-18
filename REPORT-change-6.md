# jobq change 6: the archive pruned, a speed budget, and the rename rule corrected

Change: `mo-wiki/spec/programs/01g-job-queue-change-6.md`, made to
`examples/programs/jobq/`.

**Status: done.** Every check and test is green, the budget is met, and the
commit is `jobq: change 6`.

This session continued from the work-in-progress commits made on the Linux VM
(`9efbcf8`, `e258978`) and from `REPORT-change-6-wip.md`. This session ran on a
Mac (macOS, 14 cores), and every measurement below was taken here.

## Wall-clock

| Session      | Machine  | Worked                                                          |
| ------------ | -------- | --------------------------------------------------------------- |
| Predecessor  | Linux VM | about 68 minutes, the restart gap left out (see the WIP report) |
| This session | Mac      | 09:24 to 09:47 ET, about 23 minutes                             |
| **Total**    |          | **about 91 minutes**                                            |

## The budget: the two `bench` runs

The command was `jobq bench <dir>`, with the defaults of 30,000 jobs and 32
workers. It was run against two binaries built with `mo build --surface`:

- **Change 6:** built from this worktree.
- **Change 3:** built from `git archive ca550e5` into a scratch folder, with
  this `bench.mo` copied in and the same `bench` task added to its `main.mo`.
  Its tests pass: bench 4, main 10.

The runs were one at a time, with nothing else of mine running, in the order 3,
6, 3, 6.

`bench` prints `load average before n/a`, because macOS has no `/proc/loadavg`.
The load average on each `==` line was read with `os.getloadavg()` just before
that run. Load from other sessions on the machine kept it between 5 and 7. The
folder paths are shortened to their last part below.

```
== change 3, 09:33:52, load average (os.getloadavg) 5.88 5.49 5.32
jobq bench: bench3, 30000 jobs, 32 workers; load average before n/a
creates: 30000 in 3.57 s = 8398/s
pairs, 1 worker: 7504 in 3.42 s = 2194/s
pairs, 32 workers: 22496 in 5.80 s = 3877/s
resident memory after the pairs: 68.4 MiB
restart with a 29 MB log: 1.03 s to /health
== change 6, 09:34:12, load average (os.getloadavg) 5.64 5.47 5.32
jobq bench: bench6, 30000 jobs, 32 workers; load average before n/a
creates: 30000 in 4.17 s = 7187/s
pairs, 1 worker: 7504 in 3.52 s = 2129/s
pairs, 32 workers: 22496 in 6.03 s = 3727/s
resident memory after the pairs: 75.3 MiB
restart with a 29 MB log: 1.51 s to /health
== change 3, 09:34:32, load average (os.getloadavg) 6.92 5.79 5.44
jobq bench: bench3, 30000 jobs, 32 workers; load average before n/a
creates: 30000 in 3.58 s = 8361/s
pairs, 1 worker: 7504 in 3.50 s = 2138/s
pairs, 32 workers: 22496 in 5.35 s = 4198/s
resident memory after the pairs: 61.7 MiB
restart with a 29 MB log: 1.03 s to /health
== change 6, 09:34:51, load average (os.getloadavg) 7.46 6.00 5.52
jobq bench: bench6, 30000 jobs, 32 workers; load average before n/a
creates: 30000 in 3.60 s = 8333/s
pairs, 1 worker: 7504 in 3.76 s = 1995/s
pairs, 32 workers: 22496 in 5.97 s = 3766/s
resident memory after the pairs: 73.5 MiB
restart with a 29 MB log: 1.50 s to /health
```

| Round | Creates/s, change 6 ÷ change 3 | Pairs/s at 32 workers, change 6 ÷ change 3 |
| ----- | ------------------------------ | ------------------------------------------ |
| 1     | 7187 ÷ 8398 = **0.86**         | 3727 ÷ 3877 = **0.96**                     |
| 2     | 8333 ÷ 8361 = **1.00**         | 3766 ÷ 4198 = **0.90**                     |

Both numbers are at or above 0.8× in every round, so the budget is met. Two
things got worse but are not part of the budget:

- **Restart:** 1.5 s against 1.03 s. Change 6 replays the archive and the marks
  as well.
- **Resident memory:** about 7 to 12 MiB more.

**What the budget made the maintainer change.** Change 4's postcondition on
`Board.sweep` walked every done and dead job on every request
(`ensures all_ends(result.board).all?(...)`). The predecessor replaced it with
the O(1) `ensures !looks_due?(result.board, now)`. The full walk now happens
only in `shelved`, which runs only when an archive move is due. On the VM this
took change 5's 567 pairs/s to 943, against change 3's 1,046. The runs above
confirm the result on this machine.

**An earlier round that is not the budget run.** A first pair of runs used the
bench as the predecessor left it. It printed the following:

- **Change 6:** creates 1083/s; pairs at 1 worker 132/s over 56.73 s; pairs at
  32 workers 1232/s; 73.8 MiB; restart 1.54 s.
- **Change 3:** creates 991/s; pairs at 1 worker 119/s over 62.91 s; pairs at 32
  workers 1229/s; 66.7 MiB; restart 1.20 s.

Those runs showed a bug in the bench: a pair worker never stopped at its 10 s
bound (loop 22). Chapter 3 freezes `clock.now` for a whole update, and the
worker ran all its pairs inside one update. The bench was fixed and both
programs were rebuilt before the runs above. I cannot explain why creates were
about 8× slower in that first round on both programs; the create path did not
change. The ratios in that round were 1.09 and 1.00.

## What this session did

1. **Resident memory on macOS.**
   - There is no `/proc` on macOS. `Bench.resident_mib` now takes the program's
     `Option(Runtime)` and reads `memory(...).resident_bytes` when it is `Some`.
     It falls back to `/proc/self/status` on Linux.
   - `main` sends `bench` to its own call with `platform.runtime`, because `ran`
     is already at six parameters.
   - A bench binary is built with `--surface`.
2. **The pair worker's time bound (loop 22).**
   - The clock is frozen for an update. A `Pairer` now does one round of up to
     25 pairs per `Go(me)` and sends itself the next `Go`.
   - An ask for its count is kept in state (`waiting: List(Reply(UInt64))`) and
     answered once the worker is done.
   - This follows the `processes/deferred-reply.mo` pattern.
   - A new test, "pair workers with no service to lease from are done at once,
     and each answers its count", holds under 100 seeds with faults.
3. **The checks the predecessor left.** All were run here:
   - **`sequence.py`:** passed on the first run, on a fresh folder and on
     `data/change5`.
   - **`restarts.py`:** all checks held.
   - **`mo build --tests` parity:** matches for all 8 modules.
   - **The seven `# run:` lines:** each matches its `.expected` file under
     `mo run` and as a binary.
4. **Every declared error reached.** New tests were added for the errors nobody
   reached. The table is below.
5. **`TOOLCHAIN-BUGS.md`, entries 6 to 9:**
   - 6: no `Fs` row syncs a folder, and macOS `fsync` is not `F_FULLFSYNC`.
   - 7: the `mo fmt` break the predecessor saw. It does not reproduce on this
     toolchain and is recorded as seen once.
   - 8: `for _ in 0..N` builds the whole range.
   - 9: a delayed send that re-arms itself keeps a simulated test from settling.

## Final test state

| Module | Tests       | Under `--sim 100` with faults |
| ------ | ----------- | ----------------------------- |
| job    | 36          |                               |
| store  | 15 (was 14) |                               |
| bench  | 4 (was 3)   | 1 of 1 held                   |
| board  | 48 (was 47) |                               |
| api    | 16          |                               |
| main   | 25 (was 24) |                               |
| queue  | 26          | 16 of 18 held                 |
| server | 12          | 12 of 12 held                 |

- **Queue:** the 2 tests that pass only without faults are the same two as in
  change 5. One of them, the race test, fails under one seed on the untouched
  change-5 tree too.
- **Other checks:** `mo check` and `mo fmt --check` are clean on every file.
  `sequence.py` and `restarts.py` pass against the final binary.

## Loops to green

There were 29 loops: 20 by the predecessor and 9 in this session.

| Cause                                                           | Loops                               | Count |
| --------------------------------------------------------------- | ----------------------------------- | ----- |
| Toolchain shape rules (MO0311, MO0411, MO0317, MO0208, …)       | 1, 2, 3, 4, 9, 10, 14, 23, 24, 27   | 10    |
| Test assumptions too narrow under faults, or test bugs          | 6, 7, 8, 11, 12, 13, 15, 25, 26, 28 | 10    |
| Design bugs that ran away with memory                           | 5, 19                               | 2     |
| Formatting, or an `mo fmt` bug                                  | 17, 18, 21, 29                      | 4     |
| Process slips (a stale `verified:` line, a scripted edit)       | 16, 20                              | 2     |
| A bench bug found by measuring (the clock frozen for an update) | 22                                  | 1     |

This session's loops, and whether the first fix worked:

| Loop | What failed                                                                                                    | First fix worked?                                                               |
| ---- | -------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| 21   | `mo fmt --check` on `main.mo` after the `main` edit                                                            | Yes                                                                             |
| 22   | Bench run 1: the pair worker ran 56 s past its 10 s bound, because `clock.now` is frozen for an update         | No: the redesign hit loop 23                                                    |
| 23   | MO0411: `reply_to` mentioned but not handed to a state field                                                   | Yes                                                                             |
| 24   | MO0317 on `main.mo` in both trees: Jobq.Bench, a module it uses, had changed                                   | Yes                                                                             |
| 25   | New store test: `rewritten` into a folder that is not there, on `Fs.fixture()`, is `Ok`                        | No: loop 26                                                                     |
| 26   | Same test: a fixture `write` over a folder's path is `Ok` too                                                  | No: the 120 s fixture delay then hit loop 27                                    |
| 27   | MO0208: `2.minutes` is not a Duration                                                                          | Yes                                                                             |
| 28   | The new `Unbound` test passed only without faults, because it started a process and `mkdir` failed by the seed | Yes: hold the port with a bare `listen`, so the failing serve starts no process |
| 29   | `mo fmt --check` on `api.mo` and `board.mo` (new lines past 100 columns)                                       | Yes                                                                             |

The predecessor's first fixes that did not work were loops 1, 3, and 7; see the
WIP report.

## Files changed (change 5, `23118a3`, to this commit)

- **`examples/programs/jobq/`:** `api.mo`, `bench.mo` (new), `board.mo`,
  `main.mo`, `queue.mo`, `server.mo`, `store.mo`, `sequence.py` (new),
  `jobq.expected`, `data/session.txt`, `data/change5/jobq.log` (new),
  `data/change5/jobq.archive` (new), `TOOLCHAIN-BUGS.md`.
- **`examples/programs/.mo.ids`.**
- **`REPORT-change-6-wip.md` and `REPORT-change-6.md`.**

`job.mo` and `restarts.py` are unchanged. The spec commit `4ab5c24` between them
is not this work.

## Every declared error and the test that reaches it

This covers the store, the program's commands, and the folder check. Tests named
without a file are in that group's module.

### Store (`store.mo`, `StoreError`)

- **Missing folder, `NoFolder`:** store "every way a store fails to open or to
  write whole is its own error" (new). Also main "verify takes one folder, and
  names the folder it cannot open", and the `serve data/nowhere` run line (exit
  1).
- **Folder too slow to read, `Slow`:** the same new store test
  (`Fs.fixture(delay: 1.minute)`).
- **A log that cannot be read, `Unreadable`:** the same new store test, with a
  folder where `jobq.log` should be.
- **A bad record, `BadLine`:**
  - store "replay applies SET and DEL in order, and stops open at a line that is
    neither", through `stepped` and `finished`;
  - the new store test, through `reopened`;
  - main "verify refuses an archive with a bad record, naming it, as it refuses
    a bad live one".
- **A write that fails, `Unwritten`:** the new store test, for `rewritten` and
  `compact` on a disk slower than their deadline. Also server "a store that
  cannot be written answers writes 503 over the wire and keeps answering reads",
  and the queue test in which the log refuses after the archive took.
- **A full disk, or a write that stops part way, `Torn`:**
  - store "a change the log cannot take leaves the table as it was";
  - queue "a batch the log did not take is 503, and the board goes back to what
    the store holds";
  - queue "an archive that refuses the move writes nothing to the log, and a
    torn one is written whole next time".

A full disk is reached as `Torn` or `Unwritten`, which are the two things an
append can leave behind. `Fs` has no separate full-disk error.

### Commands (`main.mo`, `Problem`)

- **`Usage`:** main "a missing folder, a bad port, a short request, or an
  unknown command is a usage error", "prune takes a folder and an age…", and the
  `serve` run line (exit 2).
- **`Unopened`:** the store errors above, as `jobq` reports them.
- **`Ill`:** main "a folder with a record no request could have left is refused,
  and a whole one is verified", and the `verify data/ill` run line (exit 1).
- **`Unbound`:** main "a serve on a port another listener holds is Unbound, and
  exits 1" (new).
- **`Unreached`:** the `client 127.0.0.1 1 p GET /jobs` run line (exit 1).

### Folder check (`board.mo` `ill_formed`, `job.mo`)

- **A rename record with a bad name** (and its key, `from`, `to`, renaming to
  itself, `next_id`, not a rename): board "a folder with a rename record that is
  not one is ill-formed by name"; main "verify refuses a folder with a bad
  rename record…".
- **A prune record with a bad cutoff** (and its key, `pruned`, not a prune):
  board "a folder with a prune record that is not one, or two marks with one
  number, is ill-formed by name"; main "verify refuses a folder with a bad prune
  record, naming it".
- **Two marks with one number:** the same board prune test.
- **A key clash, "its key k is j_N's too":** board "an archive with a bad
  record, or a key on two jobs, is ill-formed by name". Over the API, the 409 "X
  exists" on a rename is board "a rename to a queue that holds a job is 409…"
  and session lines 89, 90, and 95.
- **"an archived job is done or dead, not X":** the same board archive test,
  with a new line added. No test reached it before.
- **ids and renames "is not a number", "the next id is below j_N", "is not a
  job", "its id is X, not its key", and the tries rules:** board "a folder's
  records are ill-formed at the first key whose record breaks a rule", and job
  "a record is well-formed in each state…".
- **"its key is not 1 to 64 …" and "a live job has no archived_at" on the live
  log:** reached only by direct calls in `job.mo` ("a key follows the queue
  name's rule…", "an archived job carries archived_at…"), not through an open.

### API answers no test reached before

- **400 on a listing's queue name, and 400 on a fail reason over 4 KiB:** api "a
  body that is not JSON…", with new lines.
- **503 "X is not in a state a lease can take", "X is not a worker a lease can
  go to", and "a rename names two queues":** board "a step the API's checks keep
  out is 503 at the board, never a tripped contract" (new). These are guards
  behind the API's own checks, so only a direct call to the board step reaches
  them.
- **The 503 texts for a queue that timed out or is down (`queue.mo`):** reached
  by the queue and server fault tests through `unavailable?`, which does not
  check the exact text.

### Branches still not reached

No declared error is left unreached. These branches of reached errors have no
test:

- **`NoFolder` when `list` answers `NotText`.** No `Fs` implementation gives
  `NotText` for a list.
- **`rename` failing just after `write` succeeded, in `rewritten` and
  `compact`.** It needs a disk to fail between two calls, which the fixture
  cannot do.
- **Some `Unopened` call sites in `main.mo`:** the check files, the script read,
  and the bench `mkdir`. They report the same variant that the store tests
  reach.

## Nevers and invariants

- **Added by the predecessor:** "a prune removes a live job, or an archived job
  younger than its age".
- **Changed by the predecessor:** `Board.sweep`'s third `ensures` (the budget
  cause).
- **Tripped during the work:**
  - The new prune `never` did not trip.
  - The pure step `pruned`'s `requires`, an age of at least a second, is tripped
    by `test rejects "a prune step whose age is under a second"`.
  - MO0311 (loop 1) needed that test.
- **Added in this session:** no never or invariant.

## The change-5 folder

The change-5 program wrote rename records with no `next_id`:
`data/change5/jobq.log` holds `SET rename_2 {"from": "old-c", "to": "old-d"}`
after a compaction. Its own `verify` refuses that folder with exit 1. This
program reads such a record the change-5 way, applying it to every job before
it. It keeps the old stored count only as a floor, so it opens the folder.
`sequence.py` runs the whole sequence on a copy of that folder.

## Decisions the spec did not cover

1. **The prune's cutoff.** The cutoff is now minus `older_than_ms`, cut to
   milliseconds. A job whose `archived_at` is at or before the cutoff is pruned.
2. **Limits on `older_than_ms` and `--retention`.**
   - `older_than_ms` runs from 1,000 ms to 100 years, and any other field in the
     body is 400.
   - `--retention` is 0, or 1,000 ms to 100 years.
3. **A prune that removes nothing writes nothing.** This holds for a prune
   through the API as well as the background one.
4. **Numbering.** Renames and prunes share one numbered run, the marks. Records
   carry the count they have seen in `"renames"`, the change-5 field, kept for
   compatibility.
5. **No stored count.** The count is worked out at open. An old `renames` record
   must be only a number, and it is a floor.
6. **A mark is a batch of its own**, for a prune as for a rename.
7. **The background prune runs about once a minute.** It is armed by a call or
   by the listener's idle sweep, never by a timer that re-arms itself, so a
   simulated test ends (`TOOLCHAIN-BUGS.md`, entry 9).
8. **`GET /archive`.** `bytes` is the size of the archive file the service
   writes to, which is the `.check` file under `jobq check`. A token is
   required.
9. **Offline prune.** `jobq prune` first rewrites a torn log whole, then
   appends. It prints
   `jobq: pruned k archived jobs from <dir>; m remain; n lines written`.
10. **Bench runs in-process.** It measures from inside the program. Its
    "restart" opens the folder again into a second service, because the first
    cannot be stopped from inside the program.
11. **The folder cannot be fsynced.** No `Fs` row does it (`TOOLCHAIN-BUGS.md`,
    entry 6). `sequence.py` reports the kill between compact's rename and a
    folder sync as not placed. On macOS, `fsync` is also not `F_FULLFSYNC`.
12. **Resident memory comes from the runtime surface.** On macOS, bench reads it
    through `platform.runtime`, so a bench binary is built with
    `mo build --surface`. Its load average is `n/a` there, so the report takes
    the load average from `os.getloadavg()` just before each run.
13. **The pair worker's bound.** Because the clock is frozen for an update, a
    worker does a round of at most 25 pairs per message. It may run up to one
    round past its 10 s. Like `measure.py`, a worker stops at its queue's
    first 204. With 30,000 jobs the 1-worker phase empties `q0` well within the
    10 s, and in the 32-worker phase the 8 workers on `q0` stop at once. Both
    programs are measured the same way.
14. **The change-3 program for the budget** is `ca550e5`, the commit "jobq:
    change 3". It gets only the bench added: `bench.mo` copied as is, plus the
    same `bench` task in its `main.mo`.
