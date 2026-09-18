# jobq change 6: report (Go)

Change 6 is done and green. It covers the archive prune (on demand, in the
background, and offline), `bench` and its speed budget, the rename rule's
`next_id`, and the spec's sequence. The work began on a Linux VM, which stopped
(see `REPORT-change-6-wip.md`), and continued on a Mac: Apple M3 Max, 14 cores,
macOS, go1.27.1. Everything the predecessor measured on the VM was measured
again here.

## Wall-clock

- **This session:** 09:23 to 10:00 ET on 18 Sep 2026, about **37 minutes**. That
  includes about 15 minutes of final budget runs, during which nothing else of
  mine ran.
- **The predecessor:** about **65 minutes** on the VM, not counting the 3-hour
  outage.
- **Together:** about **102 minutes**.

## Loops to green (numbering continues from the predecessor's 1 to 4)

| #   | Cause         | Diagnostic / failing test                                                                                                                                                                                                                                                                                                                                                                                                                              | First fix worked?        |
| --- | ------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------ |
| 1   | build         | `undefined: cmdPrune` (predecessor)                                                                                                                                                                                                                                                                                                                                                                                                                    | yes                      |
| 2   | vet           | `applyArchived` signature in archive_test.go (predecessor)                                                                                                                                                                                                                                                                                                                                                                                             | yes                      |
| 3   | test          | `go test ./jobq` passed the 300 s guard (predecessor; cause unknown then)                                                                                                                                                                                                                                                                                                                                                                              | cause found in loop 5    |
| 4   | tooling       | `git archive` path from a subdirectory (predecessor)                                                                                                                                                                                                                                                                                                                                                                                                   | yes                      |
| 5   | test (hang)   | `go test -v` stalled in `TestVerifyRefusesABadRenameRecord`. It expected `verify`/`compact`/`serve` to refuse a rename record without `next_id`. The change now accepts such a record (the change-5 reading), so `serve` served forever. This was loop 3's cause. Fix: the case left the refusal table (acceptance is now `TestChange5RenameRecordWithoutNextID`), the stale "no job and no id" message was updated, and a prune-field case was added. | yes: suite green in 30 s |
| 6   | check (gofmt) | `gofmt -l` listed store.go (the predecessor's decode struct)                                                                                                                                                                                                                                                                                                                                                                                           | yes (`gofmt -w`)         |
| 7   | test          | New prune tests: 6 tests failed. Four were my own arithmetic: the young job archives at 01:01, so a 1 s prune removes 2, not 3. The other three: a Never's message names `<dir>/jobq.log`, not `<dir>:`; `jsonCompact` decodes into a job shape; and the 503 case pruned nothing, because its job had only just archived. One edit fixed all of them.                                                                                                  | yes                      |
| 8   | test          | New errors_test: 2 cases. (a) A key clash at open was reported as `jobq: never failed: …` without the folder. **This was a real defect in the message**, fixed in `openQueue` (serve.go). (b) "a job's key changes" in `applyArchiveRecord` cannot be reached from a folder, because the archive replays before the log. The folder case now uses the log's key change, and the archive branch got a direct test.                                      | yes                      |

No build failed this session. staticcheck, vet, check.sh, the logstat check, the
new next_id tests, the sequence test and `go test -race` all passed on their
first run. By cause: tests 4 (loops 3, 5, 7, 8), build 1, vet 1, gofmt 1,
tooling 1.

## Files changed (against change 5, 20b050c)

- **Changed:** api.go, bench.go (new in the WIP), board.go, check.go, check.sh,
  job.go, main.go, prune.go, queue.go, serve.go, store.go and verify.go. The
  tests changed are archive_test.go, board_test.go, main_test.go,
  rename_test.go, sim_test.go and store_test.go.
- **New:** errors_test.go, nextid_test.go, prune_test.go,
  testdata/sequence.script, testdata/sequence.expected,
  testdata/sequence-v5.expected, testdata/v5-write.script,
  testdata/v5/{jobq.log, jobq.archive}.
- **Reports:** REPORT-change-6.md (this file). REPORT-change-6-wip.md is kept.

## The two bench runs (the budget)

The command is `jobq bench <dir> --serve <binary>` with the defaults
(`--jobs 30000 --workers 32`), run by the change-6 binary. `--serve` points it
at the program measured. The change-3 program was built from
`git archive 208d62e` in a temporary directory. The runs were alternated and
repeated; nothing else of mine was running. The machine's load average (other
sessions) was about 5 to 7 throughout.

```
== run 1, change 3, 09:43:47, load average before: { 6.91 7.20 6.29 }
$ jobq bench b-c3 --serve jobq-c3
creates/s: 196 (30000 in 152.93 s, 0 errors)
pairs/s at 1 worker: 95 (477 in 5.00 s, 0 errors)
pairs/s at 32 workers: 105 (6327 in 60.26 s, 0 errors)
resident memory after the pairs: 37.6 MiB
restart seconds: 0.175
== run 1, change 6, 09:47:26, load average before: { 6.07 6.46 6.15 }
$ jobq bench b-c6 --serve jobq-c6
creates/s: 197 (30000 in 152.46 s, 0 errors)
pairs/s at 1 worker: 110 (550 in 5.00 s, 0 errors)
pairs/s at 32 workers: 105 (6304 in 60.15 s, 0 errors)
resident memory after the pairs: 40.4 MiB
restart seconds: 0.145
== run 2, change 3, 09:51:04, load average before: { 5.39 5.85 5.94 }
$ jobq bench b-c3 --serve jobq-c3
creates/s: 205 (30000 in 146.28 s, 0 errors)
pairs/s at 1 worker: 93 (468 in 5.01 s, 0 errors)
pairs/s at 32 workers: 105 (6336 in 60.28 s, 0 errors)
resident memory after the pairs: 37.7 MiB
restart seconds: 0.134
== run 2, change 6, 09:54:35, load average before: { 5.56 5.52 5.75 }
$ jobq bench b-c6 --serve jobq-c6
creates/s: 205 (30000 in 146.17 s, 0 errors)
pairs/s at 1 worker: 100 (500 in 5.01 s, 0 errors)
pairs/s at 32 workers: 106 (6382 in 60.19 s, 0 errors)
resident memory after the pairs: 39.8 MiB
restart seconds: 0.154
```

- **The budget is met.** Creates a second, change 6 against change 3: 1.01× and
  1.00×. Pairs a second at 32 workers: 1.00× and 1.01×. The floor is 0.8×.
- **What the budget made me change: nothing in the service.** On this Mac, Go's
  `File.Sync` is `F_FULLFSYNC`, about 5 ms a sync, and both programs are bound
  by it. A trial run earlier in the session gave the same picture (change 3: 203
  creates/s and 103 pairs/s; change 6: 200 and 101).
- **The VM's numbers from the WIP report are not used.** They were change 3
  against change 5 at a different fsync cost.
- **The 32-worker phase always ends at its 60 s cap**, at about 6,300 of 30,000
  pairs. The rate is read over the pairs made.
- **`bench` now reads resident memory with `ps -o rss=`**, because macOS has no
  `/proc`.

## Declared errors and the test that reaches each

The declaration is the comment in store.go. Every error below is reached by a
test that asserts its message.

| Error                                                                                                               | Test                                                                                                                     |
| ------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| a missing folder                                                                                                    | `TestOpenErrorsOfTheFolderItself`, `TestPruneCommand`                                                                    |
| a file where the folder should be                                                                                   | `TestOpenErrorsOfTheFolderItself`, `TestOpenStoreNeedsADirectory`                                                        |
| a folder in use by another jobq                                                                                     | `TestOpenErrorsOfTheFolderItself`, `TestRenameSparesAJobCreatedAfterItAndArchivedLater`                                  |
| a line that is not a record                                                                                         | `TestEveryDeclaredOpenErrorIsReached`                                                                                    |
| a bad checksum field                                                                                                | `TestEveryDeclaredOpenErrorIsReached`                                                                                    |
| a checksum mismatch                                                                                                 | `TestEveryDeclaredOpenErrorIsReached`                                                                                    |
| a record longer than 512 KiB                                                                                        | `TestEveryDeclaredOpenErrorIsReached`                                                                                    |
| a field no record has                                                                                               | `TestEveryDeclaredOpenErrorIsReached`                                                                                    |
| an unknown op                                                                                                       | `TestEveryDeclaredOpenErrorIsReached`                                                                                    |
| a put without a job                                                                                                 | `TestEveryDeclaredOpenErrorIsReached`                                                                                    |
| a bad record (an ill-formed job)                                                                                    | `TestEveryDeclaredOpenErrorIsReached`, `TestIllFormedRecordsRefuseTheFolder`                                             |
| a del of a job not held                                                                                             | `TestEveryDeclaredOpenErrorIsReached`                                                                                    |
| an arch of a job not archived                                                                                       | `TestEveryDeclaredOpenErrorIsReached`                                                                                    |
| a job archived twice                                                                                                | `TestEveryDeclaredOpenErrorIsReached`                                                                                    |
| a del of an unknown archived job                                                                                    | `TestEveryDeclaredOpenErrorIsReached`                                                                                    |
| an unknown archive op                                                                                               | `TestEveryDeclaredOpenErrorIsReached`                                                                                    |
| a bad archive record                                                                                                | `TestEveryDeclaredOpenErrorIsReached`, `TestVerifyRefusesABadArchiveRecord`                                              |
| a rename record with a bad name, or fields it cannot have                                                           | `TestEveryDeclaredOpenErrorIsReached`, `TestVerifyRefusesABadRenameRecord`                                               |
| a prune record with a bad cutoff, a count below 1, an `archive_size` outside the archive, or a field it cannot have | `TestEveryDeclaredOpenErrorIsReached`, `TestVerifyRefusesABadPruneRecord`                                                |
| a replayed prune whose count the replay does not find                                                               | `TestVerifyRefusesABadPruneRecord`                                                                                       |
| a key clash                                                                                                         | `TestEveryDeclaredOpenErrorIsReached`, `TestKeysAreCheckedAtOpen`                                                        |
| a job whose key changes (log)                                                                                       | `TestEveryDeclaredOpenErrorIsReached`                                                                                    |
| a job whose key changes (archive record over a live job)                                                            | `TestAnArchiveRecordThatChangesAKey`                                                                                     |
| a job on the board and in the archive at once                                                                       | `TestCheckApartRefusesAJobInBothPlaces`                                                                                  |
| a write that fails (503)                                                                                            | `TestAFullDiskAndAFailingWrite`, `TestAppendFailureLeavesStoreUnchanged`, `TestPruneAndArchiveRoutes` (a prune under it) |
| a full disk, ENOSPC after half a write (503, the half cut)                                                          | `TestAFullDiskAndAFailingWrite`, `TestAFullDiskUnderTheArchive`                                                          |
| a sync that fails                                                                                                   | `TestAFullDiskAndAFailingWrite`                                                                                          |
| a cut of a torn tail that fails (the store stays dirty and cuts before the next write)                              | `TestAFullDiskAndAFailingWrite`                                                                                          |
| an archive file that cannot be made (a read-only folder)                                                            | `TestReadOnlyFolderNeverTakesTheServiceDown`                                                                             |
| a compaction killed between a rename and its directory's fsync                                                      | check.sh section 9, `JOBQ_CRASH_AT` at both kill points                                                                  |

Two errors cannot be reached from a folder, because the archive always replays
before the log:

- "a job on the board and in the archive at once" (`checkApart`)
- "a job whose key changes" in the archive branch

The archive-branch check can be reached in an incremental replay (the
simulation's mirror). Both are kept as guards and reached by direct tests on a
queue built by hand. No declared error was removed.

## Nevers, invariants and contracts

- **Added:**
  - the Never "a replayed prune removes other than the count its record names"
  - the prune's `requires` (`older_than_ms` from 1,000 to a hundred years)
  - the prune's `ensures` (`ensurePruned`: every pruned job was archived at or
    before the cutoff, is gone, and frees its key)
- **"A rename never moves a job created after it"** is enforced by `next_id` in
  `rename`. It is tested with a job created into the old name and archived
  later, through a reopen, a compaction, and one more rename after the
  compaction.
- **"A folder the program wrote and closed cleanly is never refused by its own
  verify"** is covered by the sequence on both folders, including the
  generation-five steps (compact, rename, stop, verify).
- **Changed:** the rename record's shape rule. `next_id` is now optional (the
  change-5 reading), and a rename may carry no prune field.
- **Tripped during the work:** none. The only loop that touched a rule was loop
  8's unreachable archive-branch check, and it was a test design issue, not a
  trip.

## The change-5 program's rename records

The Go change-5 program always wrote `next_id` in its rename records. The folder
it wrote for this change (`testdata/v5`, from `testdata/v5-write.script` run by
the 20b050c build) has `{"op":"rename","next_id":4,…}`. So no folder it wrote
lacks the field. The change-5 reading (every id the live log has named up to
that point) is still supported, and `TestChange5RenameRecordWithoutNextID` tests
it on a hand-written log.

## The sequence

- **The script:** `testdata/sequence.script`. check.sh section 9 plays it with
  `jobq check` on a fresh folder and on a copy of `testdata/v5`, and diffs the
  output against `sequence.expected` and `sequence-v5.expected`.
  `TestSequenceMatchesExpected` does the same inside `go test`.
- **On the change-5 folder:**
  - The first reads show its rename read correctly at open: the o1 from before
    the rename is in `sales`, and the o1 from after it is in `orders`.
  - The prune removes the folder's three old archived jobs plus m1 and p1, and
    keeps m2.
  - After the generation-five steps (compact, rename, stop), the folder reopens
    and verifies.
- **The kill:** check.sh kills `jobq compact` (SIGKILL, exit 137) at
  `compact-log-renamed` and at `compact-archive-renamed`. The folder must verify
  with the same line after each, and leave no temporary file.
- **Also in section 9:** `--retention` on the served process, `--retention 999`
  refused, and the offline `jobq prune`.

## Checks run at the end (all green)

- `go vet ./...` and `staticcheck ./...`
- `gofmt -l .` prints nothing
- `go test -count=1 ./...`: 28 s for jobq
- `go test -race ./jobq`: 153 s
- `bash jobq/check.sh` and `bash logstat/check.sh`

Every one ran under guard.py.

## Decisions the spec did not cover

1. `bench` serves a child process and takes `--serve <binary>`, so the same
   client measures the change-3 program, which has no `bench` (predecessor).
2. A prune record carries `archive_size`, the archive's length when the record
   was written. The replay removes only jobs whose archive record starts before
   it, so "written before the prune record" holds even if the clock steps back
   (predecessor). `TestPruneSparesAJobArchivedAfterIt` tests this.
3. The cutoff is inclusive: a job goes when `archived_at <= now - older_than_ms`
   (predecessor).
4. `older_than_ms` has an upper bound of a hundred years, so the cutoff always
   formats (predecessor).
5. `GET /archive` `bytes` is the archive file's synced length, including pruned
   and tombstoned records until the next compaction. The route needs a bearer
   token, as every route but `/health` does (predecessor). `POST /archive/prune`
   needs one too.
6. At replay, a prune whose count does not match what it removes refuses the
   folder, as a Never (predecessor).
7. `jobq prune` prints `pruned <k>, remaining <m>`. Its arguments are exactly
   `<dir> --older-than-ms <n>`, and a usage error exits 2. It runs a look first,
   like any request, so jobs due for the archive under the default retain
   archive before the prune.
8. `--retention` takes 0 (never) or the prune's own range. The first background
   prune runs 60 s after start, not at start. A failed background prune is
   logged to stderr and tried again at the next tick. A panic or a broken rule
   in one takes the board down to be rebuilt, as a request's would. The loop
   ends before `stop` closes the store.
9. The background prune's ticks and a per-prune callback can be injected
   (`BoardConfig.pruneTicks`, `onPrune`). With the manual clock, that is the
   fixture-clock test.
10. `jobq check` gained `compact` and `verify` steps (stop, run the command,
    print its line, start) and `{id}`, the id of the last response that named
    one. One script then serves both folders, with two expected files. The
    sequence starts 3 days after the check epoch, so it comes after everything
    in the change-5 folder.
11. The change-5 folder is a checked-in fixture generated by the change-5 build
    (the script is kept next to it), rather than being built at check time from
    history.
12. An open-time Never from `checkApart` (a key clash) now names the folder:
    `jobq: <dir>: never failed: …`. It used to print no folder.
13. `bench` reads resident memory with `ps -o rss=` on Linux and macOS alike.
14. The two guards that a folder cannot reach are kept and reached by direct
    tests rather than removed. They are the job on the board and in the archive
    at once, and the archive record that changes a live job's key.
