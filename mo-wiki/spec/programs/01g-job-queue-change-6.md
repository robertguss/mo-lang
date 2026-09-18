# Program 1, change 6: the archive pruned, a speed budget, and the rename rule corrected

**Status:** sealed 18 Sep 2026, 4:40 AM ET, by Fable, before any session; generation six not yet run (`plans/erosion-round.md`). The sixth change to `jobq`, the erosion round's generation six (direction 43, measurement 3). Written after generation five, where every maintainer found the same wrong sentence in change 5's spec and Mo alone shipped a folder it would not reopen, and after the probe that named generation four's nine-times slowdown as a postcondition walking every finished job on every request. Everything in `01-job-queue.md`, `01b-…`, `01c-…`, `01d-…`, `01e-…`, and `01f-…` still holds unless a line below changes it. The shape is a product ticket with a bug report attached: operators want the archive bounded, they want the queue as fast as it was two changes ago and a way to see when it is not, and one of them could not reopen a folder after a compaction and a rename.

## What changes, in one screen

1. **The archive is pruned.** An archived job older than a retention age is removed, on demand and in the background, as one durable record; its key is freed; the count is reported.
2. **A speed budget is part of the program.** The program ships a bench command and a budget: lease-and-ack pairs a second at 32 workers no lower than 0.8× the program's own change-3 number on the same machine, and creates a second the same. The maintainer measures before and after the change and reports both; a program under the budget is not done.
3. **The rename rule is corrected.** A rename record carries the id boundary it applies to, so an archived job's queue is decided by the records before it, and a name reused after a rename is a new queue. This is the correction every generation-five maintainer made in its own way; it is now the spec's.
4. **A bug report.** After `compact`, one more rename, and a stop, the Mo program of change 5 refused to open its folder (`verify` and `serve` exit 1, "the rename count is below rename_3"). Every maintainer checks its own program against the sequence in "The sequence" below and fixes what it finds.

## The prune

```
POST   /archive/prune     {"older_than_ms": n}     → 200 {"pruned": k, "remaining": m}  |  400
GET    /archive           → 200 {"archived": m, "oldest_archived_at": "<iso>" | null, "bytes": b}
```

`older_than_ms` is an integer of at least 1,000 (`400` otherwise). A prune removes every archived job whose `archived_at` is at least `older_than_ms` before now: `GET /jobs/{id}` on it is `404` from the response on, it is in no listing, `/health` and `/archive` no longer count it, and its key is free in its queue (a create with that key is `201` and a new job). A live job is never touched by a prune, whatever its age. `pruned` counts the jobs removed; `remaining` the archived jobs left.

`--retention <ms>` on `serve` (default 0, never) prunes with that age every 60 s in the background, the same rule, the same record; a prune that removes nothing writes nothing. `jobq prune <dir> --older-than-ms n` does it offline and prints the two counts.

**The record.** A prune is one record in the live log, on disk before the response, naming the cutoff (`archived_at` before which jobs are gone) and the count; it is never one record per job. The replay applies it in order: an archive record older than the cutoff, written before the prune record, is gone at open; one written after is not. `compact` rewrites the archive without pruned jobs and folds the prune records away; `verify` checks a prune record's shape and applies it when it counts. A kill leaves the record wholly on the disk or wholly off it.

## The budget

```
jobq bench <dir> [--jobs 30000] [--workers 32]   prints creates/s, pairs/s at 1 and at 32 workers, restart seconds, resident memory after the pairs
```

`bench` starts the service on a free port in `<dir>`, creates `--jobs` jobs, leases and acks them from `--workers` concurrent clients, restarts the service, and prints one line per number, the same way the round's `measure.py` does (its columns: creates a second, pairs a second at 1 and at 32 workers, restart to `/health`, resident memory after the pairs). **The budget:** on the same machine, with nothing else running, the change-6 program's creates a second and pairs a second at 32 workers are each at least 0.8× the change-3 program's, measured by this same `bench` run against the change-3 program (the maintainer builds it from the worktree's history, `git show` the change-3 commit into a temporary directory, and runs the same command). The report carries both runs' lines as printed and the load average before each. A program below the budget is not done: the maintainer finds what the change-4 or change-5 work cost and fixes it, and says in the report what it was. The Mo maintainer is told where to look only by the budget, not by this page.

## The rename rule, corrected

Replacing the paragraph "The record" of change 5 for the archive: a rename record carries `"next_id"`, the id the service would give the next created job at the moment of the rename. A record (live or archived) whose job id is below `next_id` and whose queue is `name` at that point in the replay is in `to` from the rename on; a job created after the rename (id at or above `next_id`) into `name` is in `name`, a fresh queue. The archive is not rewritten by a rename; at open and at every read an archived job's queue is the live log's renames with `next_id` above its id, applied in order, to its record's queue. `compact` rewrites the archive with current names and keeps no rename record and no count. A folder whose live log or archive was written by the change-5 program opens: a rename record without `next_id` is read as applying to every job with an id below the highest id in the folder at that point (the change-5 reading), and the report says whether the maintainer's change-5 program wrote such records and what was done about them.

## The sequence

The program-level check script (`check.sh` or its equivalent, extended with every change) runs this sequence on a fresh folder and again on a folder the program wrote under change 5: create jobs with keys into two queues; lease and ack some; wait past `retain_ms` so some archive; `compact`; rename one queue; create into the old name; prune with an age that removes some archived jobs and not others; stop; reopen; `verify`; create again with a freed key and with a used key; lease, ack, list, `/queues`, `/archive`, `/health`. Every step's expected answer is in the script. **Persistence is named twice**: the file's contents (fsync) and the directory entry (a rename or a create of a file that survives a kill), separately, because a compaction that renames a file must fsync the directory too, and the script kills the service between the rename of the compacted file and the directory's fsync where the program lets it.

## Every declared error, reached

The store (recipe or the program's own) declares its error paths: a missing folder, a bad record, a full disk, a write that fails, a rename record with a bad name, a prune record with a bad cutoff, a key clash. The report lists every declared error and the test that reaches it; an error that no test can reach is removed from the declaration or given a test, and the report says which. The round's second acceptance question (from the research lane, 17 Sep).

## Usage

```
jobq serve <dir> [--port N] [--retain-ms N] [--retention <ms>]
jobq prune <dir> --older-than-ms <n>
jobq bench <dir> [--jobs N] [--workers N]
```

plus everything from the earlier changes, unchanged.

## Nevers

- A pruned job never comes back, restart or not.
- A prune never removes a live job, or an archived job younger than its age.
- The archived count after replay equals the count before the stop, prunes applied.
- A rename never moves a job created after it.
- A folder the program wrote and closed cleanly is never refused at open by the program's own `verify` (the generation-five bug, as a rule).
- Everything in the earlier lists still holds.

## Contracts and tests the reader expects to see

The prune as a pure step over the archive and the key map with its `requires` (the age) and `ensures` (nothing live touched; every removed job older than the cutoff; the keys freed), tested with jobs on each side of the cutoff, with a key reused after, across a restart, across a compaction, under a kill mid-record; the background prune tested with a fixture clock; the rename rule's `next_id` tested with a job created into the old name after the rename and archived later; the change-5 folder opened; the sequence script green on a fresh folder and on a change-5 folder; `bench` run twice with its lines in the report; every declared error reached, listed. The report says which `never` or `invariant` the maintainer had to change or add, which tripped during the work, and what the budget made the maintainer change.

## Measured, for the round

The round's page (`plans/erosion-round.md`) says what is measured. For the maintainer nothing is asked beyond the report: loops to green by cause, wall-clock, files changed, the two `bench` runs, and the numbered list of decisions this page did not cover.
