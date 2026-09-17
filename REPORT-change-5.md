# jobq change 5 (Go): lease handoff and queue rename

## Result

Everything is green:

- `go build ./...`, `go vet ./...`, `staticcheck ./...` and `gofmt -l` pass.
- `go test ./...` passes (jobq in about 30 s). `go test -race -count=1 ./jobq`
  passes too.
- `jobq/check.sh` prints `check.sh: ok`.

The service still writes every change to disk before the response that reports
it:

- A handoff is one `put` record, written in the request's commit.
- A rename is one `rename` record, written in the request's commit. No job moves
  in memory until that write has synced.

**Wall-clock:** about 14 minutes (822 s) from the start of the session to the commit.

## Loops to green, by cause

- **Build, vet, staticcheck, gofmt:** no failures.
- **Existing suite after the code change:** no failures.
- **New tests, first run:** 2 failures, both mistakes in the tests. The first
  fix worked for both.
  1. `TestHandoffAcrossARestart`: `jobq verify` failed with "jobq.log is in use
     by another jobq" because the test still had the folder open. Fix: close the
     queue before running verify. Fixed on the first try.
  2. `TestHandoffThroughTheAPIAndTheBoard`: a GET returned
     `503 the service is restarting`, and the test then hit a nil pointer. The
     test read the job during the board's restart without waiting for it. Fix:
     call `h.q()` first to wait out the restart, and do the same in
     `TestRenameWriteFailing`. Fixed on the first try.
- **Deliberate mutation check (not a failure of the work):** I removed each of
  the two guards in the replay of a rename against archived jobs, one at a time.
  - Removing the `unarched` guard was caught by a test.
  - Removing the `next_id` guard was caught by no test. I added
    `TestAJobCreatedAfterARenameIsNotMovedByIt`, and it now catches that
    mutation. This is a coverage loop; the first fix worked.
- **Simulation extension, `check.script` / `check.expected` and `check.sh`:**
  each passed on its first run.
- **Caught in review before any test ran:** the first version of
  `finishCompaction` removed the log's temporary file before the archive's. A
  kill between the two removals would then have installed a new archive under
  the old log. I swapped the order.

**Total:** 2 test failures and 1 coverage gap, and every first fix worked.

## Nevers and invariants

**Changed:**

- **"A job is held by two workers at once."** It is now "…, or a handoff changes
  lease_until or tries". A change that leaves a live lease leased is allowed
  only when it has the handoff's shape: same `lease_until`, same `tries`
  (`isHandoff`). Any other such change is still refused.

**Added:**

- **Never "a job changes queue but by a rename".** A `put` can never move a job
  to another queue.
- **Never "a rename lets a key name two jobs in one queue"** (`renameKeys`).
- **Ensures on the handoff:** the job is leased to `to`, with the `lease_until`
  and `tries` it had.
- **Ensures on the rename:** every job of the old queue is in the new one, and
  none is left behind.

**Tripped during the work:** none. I changed the two-workers never before
writing the handoff, which would otherwise have tripped it on every handoff. The
only nevers seen firing were in the tests written to make them fire
(`TestHandoffNevers`, `TestRenameKeysStep`).

## Files changed

In `experiments/control-run/go/jobq/`:

- **`queue.go`:**
  - `Handoff`, `handoffStep`, `ensureHandedOff` and `isHandoff`.
  - `Rename`, `renameStep`, `renameKeys`, the in-memory `rename` and
    `replayRename`.
  - `commitWith`, which lets a commit carry extra records.
  - The changed nevers.
  - The `unarched` replay state, which `checkApart` turns into arch records
    still owed to the log.
  - The rename op in `applyRecord`.
- **`store.go`:**
  - The `from` and `to` record fields.
  - `Compact` now writes both temporary files, then renames the log, then the
    archive.
  - `finishCompaction` completes or rolls back a killed compaction at open.
- **`serve.go`:** the open calls `finishCompaction` under the lock.
- **`api.go`:** the `POST /jobs/{id}/handoff` and `POST /queues/{name}/rename`
  routes.
- **`verify.go`:** `wellFormedRename`.
- **`handoff_test.go`** (new): the holder, a stranger, a run-out lease, a
  handoff to itself, A→B→C, a restart, the API with the chaos switch, the
  nevers, and the record's shape.
- **`rename_test.go`** (new). It covers:
  - the pure steps, and every job state with keys and a lease in flight;
  - renaming back, the statuses, and replay with a rename between job records;
  - compact over two renames with an old name in the archive;
  - verify on bad rename records, and a killed compact;
  - the rename's write failing (store and chaos switch), and the API;
  - a kill at every write of a run with renames, handoffs and keyed creates;
  - the two archive-naming cases.
- **`sim_test.go`:** the fault simulation now has handoffs and renames among
  four queue names, checks both against a model, and asserts that a rename's
  write failed under the faults at least once.
- **`check.sh`:** new section 8, a handoff and a rename on the served process,
  through a stop and start, a compaction and verify.
- **`testdata/check.script`** and **`testdata/check.expected`:** a handoff and
  rename block, including `restart` and a `crash` during a rename.

At the root of the worktree: `REPORT-change-5.md`.

## Decisions the spec did not cover

1. **Token rule for `to`.** The spec says `to` is a token "as the lease's is",
   then describes it as 1 to 128 bytes with no whitespace. The lease token in
   this code is 1 to 256 visible ASCII characters, so I used that rule
   (`validToken`). Any worker that can lease can then receive a handoff.
2. **`updated_at` on a handoff.** A handoff sets `updated_at` to now.
   `lease_until` and `tries` stay as they were.
3. **Handoff to the caller itself.**
   - It still needs a valid `to` and a live lease (`409` otherwise).
   - It writes nothing and leaves `updated_at` alone.
   - It still commits the look's own moves, as a read does.
4. **Handoff of an archived job** is `409`, by the same rule as ack.
5. **Order of the rename's checks, and a bad path name.**
   - Order: an empty or unknown `name` is `404` first, then `to == name` is
     `409`, then a `to` that holds jobs is `409`.
   - A bad queue name in the path is `400`, as on the lease route.
6. **"Has a job" counts archived jobs** for both the `404` and the `409`, as the
   spec's "in any state, live or archived" says. `GET /queues` still counts only
   jobs on the board, so a queue whose only jobs are archived can be renamed
   although `/queues` does not list it.
7. **Error bodies.**
   - The `409`s read `conflict: exists: queue "x" holds jobs` and
     `conflict: exists: queue "x" is the queue renamed`.
   - The `404` reads `no such queue "x"`.
8. **The rename record's format.** It is
   `{"op":"rename","from":…,"to":…,"next_id":N}`.
   - `next_id` is the id counter at the time of the rename, so a replay can tell
     which archived jobs existed then.
   - A record with `from == to`, no `next_id`, or a job or id is ill-formed.
   - Its key in error messages is `rename "a" to "b"`.
9. **When a rename applies to an archived job at open.** Read literally, the
   spec says to apply every rename in the log to an archive record's queue. That
   misplaces a job archived after a rename (tested in
   `TestAnArchiveRecordWrittenAfterARenameKeepsItsName` and
   `TestAJobCreatedAfterARenameIsNotMovedByIt`). A rename applies to an archived
   job only when:
   - it comes after the job's archive point, which is the job's `arch` record,
     or the start of the log when the log has no record of the job; and
   - the job's id is below the rename's `next_id`.
10. **A kill between the archive's write and the log's `arch` record.** Such a
    job is now owed an `arch` record at the next commit after the open; before
    this change it never got one. That gives a later rename a position to apply
    from.
11. **Compaction order changed.** A kill between the two file replacements used
    to leave a harmless mismatch. With renames it would lose them: the new log
    has no rename records, and the old archive still has the old names.

- Now both temporary files are written and synced first, then the log is renamed
  into place, then the archive.
- At open, a leftover `jobq.log.compact` means nothing was replaced, so both
  temporary files are dropped.
- A lone `jobq.archive.compact` means the log was already replaced, so the open
  installs the new archive.

12. **What "one record" means.** I read it as one rename record, not one line in
    total. The rename's single write also carries the look's moves (run-out
    leases, due jobs) and any `arch` records still owed, in that order, with the
    rename record last.
13. **The chaos switch** counts the rename's write by its records, like any
    other commit.
14. **The queued index.** On a rename, the old name's entries in the queued
    index are merged into the new name's. Entries left over from jobs that no
    longer exist are skipped when popped, as before.
15. **Tombstoned (deleted) archived jobs** do not count as jobs of a queue.
