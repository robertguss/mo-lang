# jobq (Elixir), change 6: work in progress, the VM session stopped

Spec: `mo-wiki/spec/programs/01g-job-queue-change-6.md`. Program:
`experiments/control-run/elixir/jobq/`. Elixir 1.18.5 on OTP 27.3.4 through
mise. Stopped on request so the work can move to another machine. The code is
committed as it stood: `jobq: change 6 (work in progress, the VM session
stopped)`.

## State when stopped

The last full pass (12:37 to 12:38 UTC, after the VM rebooted, load 1.0 to
2.4):

- `mix format --check-formatted`: ok
- `mix compile --warnings-as-errors --force`: ok
- `mix credo --strict`: no issues
- `mix dialyzer`: 0 errors
- `mix test`: 5 properties and 209 tests. Of three runs, two passed and one
  had 1 failure, the chaos-under-load test (see "Left to do").
- `sh check.sh`: ok, with the new section Eight: the sequence on a fresh
  folder and on a change-5 folder, `jobq prune`, a bad prune record, and a
  small `jobq bench`.
- The budget is met on the quiet machine (see below).

**Wall-clock:** about 1 h 55 min of session time, from 08:42 to about 12:40
UTC. That span includes a VM reboot of about 2 h 45 min (09:44 to 12:30 UTC),
which is not work time.

## Done

- **Prune** (`lib/jobq/prune.ex`, a pure step with `requires` and `ensures`):
  - `POST /archive/prune` and `GET /archive`.
  - `serve --retention MS`, with a background tick (`prune_every_ms`, a
    fixture clock in tests).
  - `jobq prune <dir> --older-than-ms N`.
  - One log record `{"prune":cutoff,"count":k}`, written before the response.
    A prune that removes nothing writes nothing.
  - The replay applies a prune only to jobs the log had sent off before it,
    tracked by the line each job was last named on after the first prune.
  - A compaction first appends tombstones (synced) for pruned jobs still in
    the archive, then rewrites the log with no prune records, then rewrites
    the archive.
  - `verify` checks a prune record's shape and counts its effect.
- **Rename `next_id`:**
  - Records are now `{"rename":from,"to":to,"next_id":n}`.
  - The replay moves only jobs below `n`.
  - A change-5 record without `next_id` is read as the replay's counter at
    that point.
  - My change-5 program did write such records. The fixture
    `test/fixtures/change5/data` was written by the change-5 escript built
    from history (archive, rename, compact, then one more rename), and it
    opens, serves, compacts, and prunes.
- **Bench** (`lib/jobq/bench.ex`, `jobq bench <dir> [--jobs] [--workers]
  [--serve CMD] [--seconds]`):
  - Modelled on `measure.py`.
  - It spawns the server as an OS process from a command template, so the
    same bench measures the change-3 escript.
- **The sequence** (`script/sequence.py`, called from `check.sh`): the spec's
  sequence on a fresh folder and on the change-5 folder. It includes
  compactions killed, through `JOBQ_COMPACT_STOP_AT`, after the log's rename
  and before the directory's fsync, and after each compaction step.
- **Durability:**
  - The directory is fsynced when the store creates `jobq.log` or
    `jobq.archive`, and when `jobq prune` creates the log.
  - The test fault hook can return `{:error, :enospc}`.
- **Declared errors:** listed in `Jobq.Store`'s moduledoc, each with a test.
  Two errors are handled but not declared, because no folder that opens can
  make them fail: a rename that fails, and a directory fsync that fails.
- **Replay speed:**
  - Lines are decoded and checked in parallel chunks (`Task.async_stream`,
    2,000 lines a chunk), then applied in order.
  - Opening a 100k-record log went from 1160 ms to 358 ms.
  - This made the existing test "on a log of 100,000 records /health is 200
    within a second" pass. It had failed at baseline (1376 ms) and fails the
    same way on the untouched change-5 code (1280 to 1380 ms on this VM).
- **Tests:**
  - `test/jobq/change6_test.exs`, 27 tests and 1 property. It covers the
    prune on each side of the cutoff, key reuse, restart, compaction, a kill
    mid-record, replay order, compaction kill points, the background prune,
    `next_id`, the change-5 folder, the CLI, the bench, and the declared
    errors.
  - `change5_test.exs` was updated for the new record format.
  - `never.ex` learned the prune record.

## Left to do

1. **The flaky existing test.** "the chaos switch under load over the wire …
   every 2xx job is there after" (`test/jobq/restart_test.exs:205`) asserts
   more than 100 successful creates.
   - Run alone on this VM it fails on both programs: change 6 got 55 to 91,
     and the untouched change-5 code got 56 to 77, passing once in five.
   - In the full suite it passes more often.
   - It is not caused by change 6, but the existing tests must pass. I was
     measuring how long a board restart takes on a small log when I was told
     to stop. My probe script had a bug of its own: it read the store's pid
     from the Registry before it had registered.
   - Next step: find what dominates a small-log board restart (crash-report
     logging, `Store.epoch`, the queue's registration) and shorten it, or show
     on the Mac that it passes as it stands.
2. **Rerun everything on the new machine.** Rerun every check (`mix test`
   three times) and `check.sh`, then rerun the budget bench: the change-3
   escript is built from `git show 404628b` into a temporary directory, and
   the command is `jobq bench <dir> --serve '<c3>/jobq serve {dir} --port
   {port}'`.
3. **Write the final `REPORT-change-6.md`** and commit it as `jobq: change 6`.

## Budget runs

Every run used `jobq bench <dir>` with 30,000 jobs and 32 workers, and was run
on this VM. Change 3 is the escript built from 404628b. Runs 1 to 10 were on a
VM shared with other sessions' benches (load 4 to 6). Runs 11 to 14 were right
after the reboot, on a quiet VM, and are the ones I would report.

| run | program | load before    | creates/s | pairs/s at 1 | pairs/s at 32 | rss after pairs | restart to /health |
| --- | ------- | -------------- | --------- | ------------ | ------------- | --------------- | ------------------ |
| 11  | c3      | 0.60 0.17 0.06 | 2477      | 340          | 3171          | 126.6 MiB       | 2.61 s             |
| 12  | c6      | 2.12 0.59 0.20 | 2981      | 381          | 3611          | 129.2 MiB       | 2.76 s             |
| 13  | c3      | 2.23 0.78 0.28 | 2634      | 369          | 3452          | 129.6 MiB       | 2.62 s             |
| 14  | c6      | 3.46 1.20 0.43 | 3116      | 377          | 3753          | 130.4 MiB       | 2.86 s             |

The budget is met:

- **Creates:** change 6 is 1.14 to 1.26 times change 3.
- **Pairs at 32 workers:** change 6 is 1.05 to 1.18 times change 3.

Runs 11 to 14 were taken before the replay speed-up, so the restart numbers
will differ in a rerun.

On the loaded VM (runs 1 to 7, and three preliminary pairs), the numbers
scattered widely. Change 3's own creates ranged from 1179 to 2905, and one
adjacent pair had change 6 at 0.79 of change 3 on pairs at 32 workers. A
change-5 build measured level with change 3. **The budget made me change
nothing in the program.** I first read the gap as a regression, then showed it
was noise by measuring change 5 and change 6 again.

Runs 1 to 7 (loaded VM):

| run | program | load before       | creates/s | pairs/s at 1 | pairs/s at 32 |
| --- | ------- | ----------------- | --------- | ------------ | ------------- |
| 1   | c3      | 3.79 10.93 20.51  | 1179      | 258          | 3296          |
| 2   | c6      | 4.75 10.26 19.83  | 2701      | 272          | 2608          |
| 3   | c3      | 4.71 9.63 19.26   | 2265      | 366          | 2860          |
| 4   | c6      | 5.04 9.16 18.75   | 1945      | 272          | 2689          |
| 5   | c6      | 4.39 8.37 17.98   | 2523      | 315          | 3177          |
| 6   | c3      | 4.13 7.88 17.46   | 2905      | 362          | 3255          |
| 7   | c6      | 4.56 7.57 17.00   | 2467      | 331          | 2950          |

Run 8 was cut off by the VM reboot.

## Loops so far, by cause

There were 12 failures in total. Every fix to the code or the tests worked the
first time. The environment failures were not fixed by an edit: the one fix was
the replay speed-up, and one environment failure is still open.

| #   | Cause                  | Diagnostic                                                                                                                                              | Did the first fix work?                                     |
| --- | ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------- |
| 1   | Environment (baseline) | `restart_test.exs:116` took 1376 ms against a limit of 1000 before any change. It also failed on change 5.                                              | Fixed later by the replay speed-up (loop 11).               |
| 2   | Environment (baseline) | The chaos-under-load test got 77 creates against more than 100.                                                                                         | Still open (see "Left to do").                              |
| 3   | Test compile           | `undefined function job/1` in `change6_test.exs`.                                                                                                       | Yes: added a default argument.                              |
| 4   | Tests                  | `Job.id/1` FunctionClauseError in the compaction's tombstones (a real bug in my code), and one test leased `j_3` where I expected `j_4`.                 | Yes, both.                                                  |
| 5   | Tests                  | `oldest_archived_at` expectation was wrong: `j_2` is archived at t0 + 2·retain.                                                                        | Yes: fixed the test's arithmetic.                           |
| 6   | Tests (existing)       | 4 `change5_test` failures from the new record format (`apply_all` and `Rename.jobs` arity, the `next_id` field).                                        | Yes.                                                        |
| 7   | Lint (credo)           | `Store.prune` was nested too deep.                                                                                                                      | Yes: extracted `prune_record/3`.                            |
| 8   | Tooling                | My own `timeout 600` killed dialyzer while it built its PLTs on the loaded VM.                                                                          | Yes: reran with more time.                                  |
| 9   | Dialyzer               | `missing_range`: `Prune.cutoff/2` could return a float.                                                                                                 | Yes: added the `is_integer(now)` guard.                     |
| 10  | Budget                 | The first two runs showed creates at about 0.6 of change 3.                                                                                             | Showed it was noise from machine load; no code change.      |
| 11  | Environment            | `restart_test.exs:108` failed consistently even on the quiet VM, and on change 5.                                                                       | Yes: the parallel replay brought it under 1 s, 3 of 3 runs. |
| 12  | Tooling                | My restart probe script called `Process.exit(nil, :kill)`.                                                                                              | Not fixed: stopped here.                                    |

`check.sh` passed on its first run every time.

## Nevers and invariants

- **Added to the log checker (`never.ex`):** a prune record names no job.
- **Added to the folder check at open:**
  - A prune record's shape.
  - A rename's `next_id`.
- **Tested:**
  - A pruned job never comes back, across a restart, a compaction, and a
    compaction killed at each step.
  - A prune never touches a live job.
  - The archived count after replay equals the count before the stop.
  - A rename never moves a job created after it.
  - The change-5 folder is never refused.
- **Tripped:** none of the nevers tripped. The compaction tests caught the
  `Job.id/1` crash in my own tombstone code.

## Decisions the spec did not cover, so far

1. **The prune's cutoff is inclusive:** a job goes when
   `archived_at <= now - older_than_ms`.
2. **The prune record format** is `{"prune":cutoff,"count":k}`, with a count
   of at least 1. The count is informational and is not checked against what
   the replay removes.
3. **A prune that removes nothing writes nothing,** for an API call as well
   as a background one.
4. **`older_than_ms` limits:** at most 2^53−1. A string or a float is `400`.
5. **`GET /archive`:**
   - `bytes` is the archive file's size on disk.
   - `oldest_archived_at` is found by scanning the archive.
6. **"Written before the prune record"** is read by log order: the line where
   the log last named the job (its archived word, or its live record when a
   kill cut a move short). A job the log names after the prune is not
   reached by it.
7. **Compaction appends synced tombstones for pruned jobs first,** so a kill
   between the log's rewrite and the archive's cannot bring them back.
8. **`--retention`:**
   - It is 0 or at least 1,000, otherwise a usage error (exit 2).
   - The background prune takes a look first, then prunes.
   - The 60-second interval is fixed; only tests change it.
9. **`jobq prune`:**
   - It prints `pruned k; remaining m`.
   - It uses the system clock.
   - It takes no lock, like `compact`.
10. **A legacy rename without `next_id`:** "below the highest id at that
    point" is read as the replay's counter, which includes the highest id
    itself.
11. **A rename's `next_id`** is the queue's counter at the time of the rename.
    The folder check refuses a `next_id` below 1, and doesn't check that it is
    at or below the counter.
12. **The bench:**
    - It is an OS-process server from a command template.
    - It follows `measure.py`: 8 producers, 100-byte payloads, 4 queues, and
      pairs at 1 worker and then at N workers, 10 s each or until the queues
      are empty.
    - RSS is the maximum over the server's process tree.
    - The restart is `SIGTERM`, then the time to a `200` on `/health`.
13. **The compaction kill hook** is the environment variable
    `JOBQ_COMPACT_STOP_AT` (`tombstones`, `log`, or `archive`), which exits
    137 at that point.
14. **Directory fsync** when the store or `jobq prune` creates a file.
15. **The sequence is a Python script** rather than a `check.script`
    transcript, because the prune's age is computed from the `archived_at`
    values it reads.
16. **The change-5 fixture** was generated by the change-5 escript built from
    history. The sequence's queues (`alpha`, `beta`, `gamma`) are distinct
    from the fixture's.
17. **Keys:** a pruned job's key is freed only when the key map entry names
    that job.
18. **Replay parallelism** was added to meet an existing test's time limit on
    this VM. It is not a spec requirement.
