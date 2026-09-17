# jobq change 5: report

Change: a lease handed off to another worker (`POST /jobs/{id}/handoff`), and a
queue renamed with jobs in flight (`POST /queues/{name}/rename`), as in spec
`01f-job-queue-change-5.md`, for the Python program in
`experiments/control-run/python/jobq/`.

## Result

All checks pass:

- `ruff check`: clean.
- `mypy --strict`: clean (26 files).
- Unit tests: 304 pass (261 before, plus 43 new ones in
  `tests/test_change5.py`). Run with
  `uv run python -m unittest discover -s tests`.
- The fault simulation (100 seeds) now also runs handoffs and renames, under
  file faults, dropped sockets, and board failures after the write. Over the 100
  seeds: 56 handoffs and 62 renames answered, and 31 renames met a 503.
- `check.sh`: prints `ok`. It has a new handoff and rename transcript: a check,
  then verify, compact, a second check, and verify.

`ruff format --check` still reports the same 5 files it reported before this
change (the formatter's Python 3.14 rewrite of `except (A, B):`). I left them
alone.

**Durability:**

- **Handoff:** a `put` record written through `_commit`, so it is fsynced before
  the response. It counts for `--crash-every`.
- **Rename:** one `rename` record (`{"kind":"rename","name":…,"to":…}`), fsynced
  before the response. It is written after every check and before the board
  changes. It counts as one change for `--crash-every`.
- **Failed write:** a write that fails leaves the board as it was (503).

**Kill run under load:** I wrote a separate script (in my scratchpad, not the
repo). It served a folder with `jobq serve` and ran 6 worker threads (keyed
creates, leases, 0 to 2 handoffs per lease, acks, and checks that the old
holder's ack is 409). A renamer thread renamed the busy queue to a fresh name
about every 50 ms. The script sent SIGKILL to the server at a random moment, 4
times on the same folder. After each reopen, `verify` passed and:

- No acknowledged job was missing.
- Every acknowledged ack was `done`.
- Every acknowledged handoff was held by its new worker. A handoff that was
  written but never answered was also accepted.
- No job created before an acknowledged rename was sent was still in the old
  name.
- No key named two jobs in one queue.

At the end the folder held 16,155 jobs, 176 queues, and 175 rename records.
Memory stayed well under 4 GB (the script watched it).

## Wall-clock

About 15 minutes from reading the spec to this report (by `date` at the start
and at the end).

## Loops to green: 13 failures

| #   | Cause                                   | Diagnostic or failing test                                                                                                                                                                          | Did the next edit fix it?                                                                            |
| --- | --------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| 1   | my test invocation                      | `unittest discover -s .` run from inside `tests/` gave `errors=1`                                                                                                                                   | yes (`-s tests` from the project)                                                                    |
| 2   | failure already there before the change | baseline `check.sh` diff: the round 7 fixture's done and dead jobs date from 15 Sep, so the default one-day retention now archives them (`{"error":"archived"}`, `archived 2`)                      | yes (`check.sh` moves the fixture copy's `*_ms` times to now)                                        |
| 3   | lint                                    | ruff RUF005 (list concatenation in `rename_step`), plus I001, which ruff fixed itself                                                                                                               | yes                                                                                                  |
| 4   | existing tests meet the new rules       | `test_an_archived_job_is_deleted_…`: the compacted counter line gained `"renames":0`. `test_a_job_is_never_held_by_two_workers_at_once`: a second lease now tripped "a handoff never changes tries" | yes (renames left out while 0; a changed `tries` on leased→leased uses the two-workers message)      |
| 5   | bugs in my new tests                    | `test_change5`: 4 subtests expected the wrong refusal wording (`rename.name value error, …`); one test read `archived_count` without a look                                                         | yes                                                                                                  |
| 6   | bug in my sim code                      | `seed 11: only the holder hands a lease off`. The sim's beliefs are lossy (a lease's answer can be dropped), so the check must use the server's state from before the request                       | yes                                                                                                  |
| 7   | bug in my sim code                      | `seed 26: a rename changes nothing but the queue`. The rename's own look can archive a finished job (`archived_ms` set)                                                                             | yes                                                                                                  |
| 8   | sim coverage floor                      | `archived_reads 7 not greater than 10`: the new steps took share away from `finish`                                                                                                                 | no (after re-sharing: 9)                                                                             |
| 9   | sim coverage floor                      | `archived_reads 9 not greater than 10`                                                                                                                                                              | yes (new steps take share from list/queues/health; a rename reads back an archived job it moved: 12) |
| 10  | lint and type                           | ruff PLR0912 in the sim's `verify` and `step`; mypy arg-type in `test_change5` (`model_copy(update=object)`)                                                                                        | yes                                                                                                  |
| 11  | expected output changed by the spec     | `check.sh` diff: the new handoff and rename transcript (read through, then accepted)                                                                                                                | yes                                                                                                  |
| 12  | bug in my `check.sh` addition           | "the compacted log still holds a rename record": the second run renames again after the compaction                                                                                                  | yes (compact once more, outside the transcript, before the grep)                                     |
| 13  | bug in my kill-run harness              | `wrong 1`: a handoff that was durable but never answered left the job with its new worker                                                                                                           | yes (the pending target is accepted)                                                                 |

I also made one slip of my own that I caught before the next run, so it is not
counted above. I ran `ruff format` over `src` and `tests`, and it rewrote the 5
files that already failed the formatter. I restored the three test files from
git and put back the parentheses in `api.py` and `queue.py`.

**By cause:**

- My test, sim, or harness code, or my invocation: 7 (#1, 5, 6, 7, 12, 13, and
  #4 in part). The first fix worked in all of them.
- Lint and type: 2 (#3, 10). The first fix worked in both.
- Sim coverage floor: 2 (#8, 9). The first fix did not work; the second did.
- Expected output changed by the spec: 1 (#11). The first fix worked.
- Failure already there before the change (time-dependent fixture): 1 (#2). The
  first fix worked.
- No failure came from the product code's logic. One product bug was caught by
  reading, before any run: a handoff would have pushed a second entry for the
  same deadline onto the lease heap. A single look would then have returned the
  job twice and broken the counts. `_apply` now skips re-indexing a
  leased→leased change, and
  `test_the_handed_off_lease_runs_out_once_at_its_old_deadline` covers it.

## Nevers and invariants changed or added

- **Changed: "a job is never held by two workers at once".**
  - Before: leased→leased was refused outright.
  - Now it is a legal edge, but only as a handoff (`check_handoff`):
    - the worker changes and is never empty;
    - `tries` is unchanged (a changed `tries` is a second lease, and is still
      reported as "never held by two workers");
    - `lease_until` is unchanged;
    - the lease is live at the change;
    - nothing but the worker and `updated_ms` changes.
  - A handoff to the holder itself writes nothing.
- **Changed: "a job's fields are fixed" (the `queue` part).** It still holds for
  every state transition. The queue moves only through the rename step, which
  has its own nevers (`check_renamed`):
  - it moves exactly `name`'s jobs, live and archived;
  - it changes nothing but `queue`;
  - it never lets a key name two jobs in one queue;
  - a key used in `name` is free in `name` afterwards;
  - it never touches a lease: same worker, same `lease_until`, checked over the
    whole board.
- **Added contracts:**
  - `rename_step` requires the target to be empty of jobs and keys, and a
    different name.
  - `compact` ensures that renames are folded (no rename record is left, and the
    count carries on).
- **Tripped during the work:** only the existing
  `test_a_job_is_never_held_by_two_workers_at_once`, whose second lease met the
  new handoff check under a different message (#4). No never or invariant
  tripped in the simulation or the kill run.

## Files changed

Under `experiments/control-run/python/jobq/`:

- `src/jobq/jobs.py`: the handoff `to` rule (1 to 128 visible ASCII),
  `HandoffRequest`, `RenameRequest`, and `RenameOut`.
- `src/jobq/store.py`:
  - `RenameRecord` and its replay (`rename_jobs`), and a rename count
    (`renames`).
  - `ArchivePutRecord` (an archive `put` stamped with the rename count) and
    `CounterRecord.renames`; both leave the field out while it is 0.
  - The archive applies only the renames written after it.
  - Verify refuses an archive record whose count is ahead of the log's.
  - Compaction folds renames and carries the count.
- `src/jobq/queue.py`:
  - `Queue.handoff` and `Queue.rename`, and the pure `rename_step`.
  - The leased→leased edge with `check_handoff`, and `check_renamed`.
  - Archive writes stamped with the rename count, and no lease re-index on a
    handoff.
- `src/jobq/api.py`: the two routes.
- `tests/test_change5.py`: new, 43 tests.
- `tests/test_sim.py`: handoff and rename steps, their checks, and new coverage
  floors.
- `check.sh`: the round 7 fixture's times moved to now; the handoff and rename
  transcript with verify and compact; checks that renames are in the log and
  gone after a compaction.
- `checks/handoff-rename-first.txt` and `checks/handoff-rename-second.txt`: new.
- `checks/expected.txt`: the new transcript.

At the worktree root: `REPORT-change-5.md` (this file).

## Decisions the spec did not cover

1. **The archive and renames: a rename count, not "apply every rename".**
   - The problem: the spec says an archived job's queue is the live log's
     renames applied to the archive record's queue. Taken literally, that breaks
     once a name is reused. After `a→b`, a fresh `a` job archived later would be
     moved to `b` at the next open.
   - The fix: each archive `put` carries `renames`, how many rename records the
     log had held when the archive record was written. At open only the renames
     after that count apply.
   - Compaction: it writes the count into the `counter` line and into every
     rewritten archive line. A kill between the archive's rewrite and the log's
     therefore applies no rename twice (tested).
   - An archive record whose count is ahead of the log's refuses the folder.
2. **Record shapes:**
   - A rename is `{"kind":"rename","name":"<old>","to":"<new>"}`.
   - `renames` is written only when it is not 0, so folders that were never
     renamed keep their old bytes, and existing tests pass unchanged.
3. **The `to` rule for a handoff:** 1 to 128 visible ASCII characters (no
   whitespace, no control, no non-ASCII). The spec says "as the lease's is", but
   this program's bearer tokens allow 256. I took the spec's 128 for `to` and
   did not shrink the bearer token rule.
4. **`updated_at` on a handoff:** it moves to the time of the handoff. I read
   "unchanged apart from `updated_at`" as meaning that `updated_at` does change.
5. **A handoff to the holder itself:** answers 200 with the job exactly as it
   was, with no write and no `updated_at` change. It does not count for the
   chaos switch.
6. **Handoff refusal order:**
   - A bad body is 400 before anything else.
   - An unknown id is 404.
   - An archived job is 409, as `ack` is.
   - A queued or finished job, a stranger, or a run-out lease is 409, with
     `ack`'s message.
7. **A malformed `{name}` in the rename path** is 400, as on `/lease`, rather
   than 404.
8. **Rename error bodies:**
   - 409 is `{"error":"exists"}` both for a used target and for `to == name`.
   - 404 is `{"error":"no such queue"}`.
   - Checks run in this order: 400 on the body, then 404, then 409. So
     `to == name` on an empty queue is 404.
9. **A queue holding only archived jobs** can be renamed (the spec's "any
   state"), although `/queues` does not list it. A target holding only archived
   jobs is refused with 409.
10. **What `moved` counts:** live and archived jobs together. It is never 0,
    because a queue with no jobs is 404.
11. **The rename's look:** like every operation, the rename first returns
    run-out leases, queues due jobs, and archives finished ones. Those writes
    come before the rename record.
12. **Chaos:** a rename counts as one change for `--crash-every`, whatever the
    number of jobs it moves. The failure comes after the rename record is on
    disk, so the rebuilt board shows the rename.
13. **In-memory waiting heap:** the queued heap of `name` is merged into `to`'s
    and re-heapified. The lease heap is keyed by job number and left alone, and
    a handoff does not push a second entry.
14. **Replay cost:** each rename record rewrites the replayed job map (O(jobs)
    per rename at open). Compaction folds them away. I accepted this rather than
    keeping an alias table.
15. **Verify's refusal text for a bad rename record** names the line, as for any
    record without a job number, for example
    `record line 2: rename.name value error, queue must be …`. Verify's success
    line is unchanged and counts jobs after renames.
16. **The time-dependent `check.sh` failure that was already there:** I fixed it
    by moving the round 7 fixture copy's millisecond times to now, keeping the
    old field names the later grep checks for. I did not add `--retain-ms` to
    `jobq check`, and I did not edit the fixture file.
17. **Program-level check:** a new pair of `jobq check` scripts with a verify
    and a compaction between them, rather than new lines in the existing
    scripts, so the earlier transcripts stay as they were.
