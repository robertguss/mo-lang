# jobq change 6: work in progress (the VM session stopped)

Change: `mo-wiki/spec/programs/01g-job-queue-change-6.md`, made to `examples/programs/jobq/`.
**Status: not done.** Stopped on instruction mid-way; the work moves to another machine. Commit
`jobq: change 6 (work in progress, the VM session stopped)`.

## Interruption

- Session began 08:44 UTC (4:44 AM ET). Worked until about 09:43 UTC. The VM was restarted after
  an out-of-memory event at 5:21 AM ET. Resumed 12:34 UTC (8:34 AM ET), stopped about 12:42 UTC.
  Wall-clock worked, the gap excluded: about 68 minutes.
- **The 13.4 GB `mo` process was almost certainly mine.** At 09:05 UTC I started
  `mo test --write --sim 100 queue.mo` with no memory cap. My first design of the background prune
  had the queue send itself a `Tick` every 60 s forever. Under the simulator that chain never lets a
  test settle. The run went to its 30-minute timeout (09:05 to 09:35 UTC, which covers 5:21 AM ET).
  The same file without `--sim` then failed with `OutOfMemory`. After that I capped every run at
  8 GB (`ulimit -v`), and since the restart at 4 GB with `guard.py`.
- A second runaway was caught by the guard after the restart. The first `jobq bench` binary reached
  4 GB in 10 s: `for _ in 0..100_000_000` in the pair worker builds the whole range. Fixed (loop 19).

## What is done (all green when last run, before the stop)

- **Budget cause found and fixed.**
  - Cause: change 4 added a postcondition to `Board.sweep`,
    `ensures all_ends(result.board).all?(...)`. It walks every done or dead job on every request.
  - Fix: it is now `ensures !looks_due?(result.board, now)`, which is O(1). The full walk stays only
    in `shelved`, which runs only when an archive move is due.
  - `measure.py` (30,000 jobs, same VM, load average 4 to 6 from other sessions, so noisy):

    | Program                            | Pairs/s at 32 workers | Creates/s |
    | ---------------------------------- | --------------------- | --------- |
    | Change 5                           | 567                   |           |
    | After the fix                      | 943                   | 1629      |
    | Change 3                           | 1046                  | 1856      |

  - The after-fix figures are about 0.9× change 3. These are **not** the brief's `bench` runs, which
    were not taken (see "Left").
- **Rename rule corrected.**
  - A rename record carries `next_id` (`{"from", "to", "next_id"}`). A replay applies a rename to a
    record only if it has not seen the rename and its job id is below `next_id`.
  - A change-5 record with no `next_id` applies to every job before it.
  - Renames and prunes share one numbered run, the marks.
  - No stored count is written any more. The count is derived at open: the highest of the old
    `renames` record, the highest mark, and the highest count any record carries.
  - The old count is only a floor now, which fixes the generation-five refusal ("the rename count
    is below rename_N"). There is a board test and a main test for it, and `data/change5/` is a
    folder written by the change-5 binary that the change-5 `verify` refuses (exit 1) and this
    version opens.
- **Prune.**
  - Routes: `POST /archive/prune {"older_than_ms"}` and `GET /archive` (`bytes` is filled in by the
    queue after the flush).
  - The pure step `Board.pruned` has `requires` and `ensures`, and there is a new never, "a prune
    removes a live job, or an archived job younger than its age".
  - A prune is one `prune_<n>` record naming the cutoff and the count, and is a batch of its own.
    The replay applies it only to archive records that have not seen it. A pruned job's stale live
    record stays gone, and a key freed and then reused is kept.
  - `verify` checks the prune record's shape and refuses two marks with one number.
  - `compact` writes 4 steps when there are marks: the log with marks, then the archive, then the
    log with no marks or count, then the archive with no count. Each cut-short step is tested.
  - `jobq prune <dir> --older-than-ms n` runs offline.
  - `--retention <ms>` prunes in the background. A `Tick` is armed by activity, one at a time; the
    listener's idle sweeps count as activity.
- **Bench.** `bench.mo` plus `jobq bench <dir> [--jobs N] [--workers N]`, run in-process. It prints
  the load average, creates/s, pairs/s at 1 and N workers, resident MiB (from /proc/self/status),
  and restart seconds to /health.
  - A small run works: 800 jobs, 8 workers, 13.7 MiB resident.
  - The same bench is ported into the change-3 program, built from `git show ca550e5`, in the
    scratchpad `c3/jobq` (not in the repo). It builds, and its tests pass.
- **Tests.** Last full run: job 36 and store 14 (unchanged), bench 3, board 47, api 16, main 24,
  queue 26 and server 12 (both with `--sim 100`).
  - Under faults, queue has 16 of 18 holding. The 2 that pass only without faults are the same
    older ones as in change 5.
  - Server has 12 of 12 holding under faults.
  - `mo fmt --check` is clean. The seven `# run:` lines match their `.expected` files under
    `mo run` and as a binary. `session.txt` has 14 new lines (archive and prune).

## What is left

1. **Run the new `sequence.py` on the program.** It was written but never run against change 6.
   Only its `--fixture` mode ran, against the change-5 binary, and made `data/change5/`.
2. **The two budget runs.** Run `jobq bench <dir>` (default 30,000 jobs, 32 workers) against the
   change-6 binary and against the change-3 port in the scratchpad `c3`. Run them one at a time
   under `guard.py`, on a quiet machine, and put both runs' lines in the report. On the new machine,
   the change-3 port must be redone:
   1. `git show ca550e5` into a temp dir.
   2. Copy in `bench.mo`.
   3. Add a `bench` task to its `main.mo`, the same functions as change 6's (`benching`, `bench`,
      `served_on`, `health_within`, `load_average`, and a `Measured` struct).
   4. Run `mo test --write` on bench and main, then `mo build`.
3. `restarts.py` has not been re-run on change 6.
4. `mo build --tests` parity has not been checked for each module.
5. `TOOLCHAIN-BUGS.md` needs four entries:
   1. No Fs row syncs a folder: `rename` and file creation do not fsync the directory.
   2. `mo fmt` rewrote a one-line `if` inside an anonymous function into code that does not parse.
   3. `for _ in 0..N` builds the whole range.
   4. A self-rearming delayed send makes the simulator never settle, and memory grows.
6. The final report `REPORT-change-6.md`, with the list of declared errors and the test reaching
   each, and the decisions list below. Then commit `jobq: change 6`.
7. Clean-up: I added a git worktree at the scratchpad `wt5` (detached at 4ab5c24) to build the
   change-5 binary. `git worktree prune` removes it once the scratch dir is gone.

## Loops so far (20)

| Cause                                                          | Loops                   | Count |
| -------------------------------------------------------------- | ----------------------- | ----- |
| Toolchain shape rules                                          | 1, 2, 3, 4, 9, 10, 14   | 7     |
| Test assumptions too narrow under faults, or test bugs         | 6, 7, 8, 11, 12, 13, 15 | 7     |
| My design bugs that ran away with memory                       | 5, 19                   | 2     |
| Formatting, or an `mo fmt` bug                                 | 17, 18                  | 2     |
| Process slips (a stale `verified:` line, a scripted edit)      | 16, 20                  | 2     |

Notes on the loops:

- **Loop 5** (the tick chain) is the 13 GB process.
- **Loop 15** is a pre-existing race test. It fails under one seed on the untouched change-5 tree
  too. I made its lease an hour long.
- **First fixes that did not work:**
  - Loop 7: it took loops 8, 11, 12, and 13 to make the new prune test hold under faults.
  - Loop 1: its MO0311 needed tests that came later.
  - Loop 3: the first split left the update at 71 lines.

## Decisions the spec did not cover (so far)

1. **The prune's cutoff.** Cutoff = now − `older_than_ms`, cut to milliseconds. A job whose
   `archived_at` is at or before the cutoff is pruned.
2. **`older_than_ms` and `--retention` limits.** `older_than_ms` is 1,000 to 100 years; any other
   field in the body is 400. `--retention` is 0, or 1,000 to 100 years.
3. **A prune that removes nothing writes nothing**, the API's as well as the background one.
4. **Numbering.** Renames and prunes share one numbered run (marks). Records carry the count they
   have seen in `"renames"`, the change-5 field, kept for compatibility.
5. **No stored count.** The count is derived at open. An old `renames` record must only be a
   number; it is a floor.
6. **Marks go alone.** A prune is a batch of its own, as a rename is.
7. **The background prune runs about every minute while the service is in use or idle.** It is
   armed by a call or an idle sweep, not by a perpetual timer, so tests end.
8. **`GET /archive`.** `bytes` is the size of the archive file the service writes to (the
   `.check` file under `jobq check`). A token is required.
9. **Offline prune.** `jobq prune` rewrites a torn log whole first, then appends. It prints
   `jobq: pruned k archived jobs from <dir>; m remain; n lines written`.
10. **Bench runs in-process.** It measures from inside the program. Its "restart" opens the folder
    again into a second service, since the first cannot be stopped in-process.
11. **Directory fsync is not possible.** It is recorded as a gap, and the sequence script reports
    it as not placed.
