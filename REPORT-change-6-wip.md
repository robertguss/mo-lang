# jobq change 6: report, work in progress (the VM session stopped)

The work stopped because it moves to another machine. Nothing here is green or accepted, and the commit is not "jobq: change 6".

## Timeline and interruptions
- Started 18 Sep 2026, 08:44 UTC (4:44 AM ET). Worked until about 09:40 UTC (5:40 AM ET).
- The VM went out of memory at 5:21 AM ET and was restarted at 8:30 AM ET. The work resumed at 12:34 UTC (8:34 AM ET) and stopped at about 12:45 UTC (8:45 AM ET) on the lead's instruction.
- Wall-clock without the gap: about 65 minutes.
- The 13.4 GB process that caused the OOM was a `mo` process in the Mo maintainer's session. It was not from this session: this session ran only `go`, the `jobq` binaries it built, and python3.

## Done (uncommitted until this WIP commit)
- `jobq/bench.go`: `jobq bench <dir> [--jobs N] [--workers N] [--serve <binary>]`.
  - It serves `<dir>` from a jobq binary in a child process on a free port. The default binary is itself; `--serve` points it at an older build, such as change 3's, which has no `bench` command of its own.
  - It creates the jobs from 8 producers into 4 queues with 100-byte payloads.
  - It runs lease-and-ack pairs twice: 1 worker for a quarter of the jobs (at most 5 s), then `--workers` workers for the rest (at most 60 s).
  - It reads RSS from /proc, restarts the service, and prints one line per number.
- `main.go`: adds the `prune` and `bench` commands. `prune.go` is still a stub that answers "todo".
- `store.go`:
  - New prune-record fields: `cutoff`, `count`, `archive_size`.
  - `replayAt` passes each record's offset to its caller, so an archived job knows where its record sits in the archive.
  - A `JOBQ_CRASH_AT` kill point (`compact-log-renamed`, `compact-archive-renamed`) sits between each compaction rename and the fsync of its directory, so check.sh can kill there.
- `queue.go`:
  - `pruneStep`, a pure step: archived jobs with `archived_at <= cutoff` whose archive offset is below `archive_size`.
  - `Queue.Prune`: one `prune` record in the live log, written before any job goes, then the jobs are forgotten and their keys freed. It checks `ensurePruned` afterwards. A prune that finds nothing writes nothing.
  - `replayPrune`: removes the same jobs at open and treats a count mismatch as a Never.
  - `Queue.Archive` answers GET /archive.
  - Each archived job keeps its archive offset (`archOff`).
  - `logNext` gives a rename record without `next_id` the change-5 reading: every id the live log has named so far.
- `job.go`: `requireOlderThanMS`, which allows 1,000 to 3,153,600,000,000 ms (a hundred years).
- `verify.go`:
  - New `wellFormedPrune`, which checks the cutoff format, a count of at least 1, an `archive_size` within the archive, and no other fields.
  - `wellFormedRename` now accepts a record without `next_id`.
- `serve.go`: `openQueue` sets `q.archive` before the log replays, so a prune record can be checked against the archive's size.
- Tests were adapted to the new `applyArchived(rec, off)` signature: board_test (`memStoreAt`), store_test, archive_test, rename_test, and sim_test.

## Left to do
- `prune.go`: the offline `jobq prune <dir> --older-than-ms n`.
- The API routes `POST /archive/prune` and `GET /archive`.
- `serve --retention <ms>`: the background prune every 60 s, with a way for tests to drive it with a fixture clock.
- Tests for prune: jobs on each side of the cutoff, a key reused afterwards, a restart, a compaction, a kill in the middle of the record, and a bad prune record in `verify`.
- Tests for `next_id`: a change-5 record without `next_id`, and a job created into the old name after a rename and archived later.
- check.sh section 9: the spec's sequence on a fresh folder and on a folder the change-5 binary wrote (to be generated into `testdata/v5`), plus the `JOBQ_CRASH_AT` kill.
- A declared-errors list, with the test that reaches each error. ENOSPC probably needs a new test.
- The full suite has to go green. **The last run (under guard.py) timed out at 300 s.** It is not yet known whether one test hangs with the new code or whether the suite simply needs more than 300 s. The next step is `go test -v`, to find the running test.
- staticcheck, gofmt (store.go needs `gofmt -w`), the budget runs, the final report, and the commit "jobq: change 6".
- The change-5 Go program always wrote `next_id` in its rename records, so no folder it wrote has a record without it. The missing-`next_id` reading is supported anyway.

## Loops so far (a loop is a failed check, build, or test)
1. Build: `undefined: cmdPrune`. main.go had been wired before prune.go existed. A stub fixed it on the first try.
2. Vet: `q.applyArchived` had the wrong signature for `replay` in archive_test.go. Changing the test helpers to `replayAt` fixed it on the first try.
3. Test: `go test ./jobq` hit the 300 s timeout under the guard. Its cause is not yet known.
4. Tooling, not a code loop: `git archive` was given a path relative to the repo root while the shell was in a subdirectory. Running it from the root fixed it on the first try.

## Budget runs so far (no final runs were made)
The runs used this session's bench build on the VM. No change-6 program was measured.

The first pair ran at 08:46 UTC, load average 0.38, 30,000 jobs:

| | change 3 (208d62e) | change 5 (20b050c) |
|---|---|---|
| creates/s | 764 | 548 |
| pairs/s at 1 worker | 430 | 259 |
| pairs/s at 32 workers | 340 (60 s cap reached) | 272 (60 s cap reached) |
| RSS after the pairs | 38.6 MiB | 42.0 MiB |
| restart | 0.525 s | 0.563 s |

- At 4,000 jobs the two programs were about equal:
  - change 3: 865 creates/s; pairs 386 at 1 worker, 334 at 32 workers.
  - change 5: 881 creates/s; pairs 399 at 1 worker, 467 at 32 workers.
- A second change-5 run at 30,000 jobs, with strace attached part of the time, gave 899 creates/s, 352 pairs/s at 1 worker, and 428 pairs/s at 32 workers.
- A later pair of runs timed out at a load average of 43, because other sessions were loading the disk.
- Reading so far: the server is fsync-bound, at about 10% CPU. The variance between runs is larger than the change-3 to change-5 gap, so no regression has been shown yet.
- The final runs must be alternated and repeated on a quiet machine.
- Note: `--jobs` 30,000 does not drain within the 60 s cap at 32 workers on this VM, so that cap may need raising.

## Decisions the spec did not cover (so far)
1. `bench` serves a child process and takes `--serve <binary>`, so the same client can measure change 3.
2. A prune record carries `archive_size`, the archive's length when the record was written. The replay removes only jobs whose archive record starts before it, so "written before the prune record" is exact even if the clock steps back.
3. The cutoff is inclusive: a job is removed when `archived_at <= now - older_than_ms`.
4. `older_than_ms` has an upper bound of a hundred years, so the cutoff always formats.
5. `GET /archive` `bytes` is the archive file's whole synced length, including pruned and tombstoned records until the next compaction. The route needs a bearer token, like the other routes apart from /health.
6. At replay, a prune whose count does not match what it removes refuses the folder, as a Never.
