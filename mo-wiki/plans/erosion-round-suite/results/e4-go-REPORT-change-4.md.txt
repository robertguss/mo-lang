# jobq change 4: idempotent creates, and old jobs archived out of the log

Spec: `mo-wiki/spec/programs/01e-job-queue-change-4.md`. Go program in
`experiments/control-run/go/jobq`.

## Result

All green:

- `gofmt -l` is empty.
- `go vet ./...` and `staticcheck ./...` are clean.
- `go test ./...` passes: contract, jobq (about 28 s), logstat.
- `go test -race ./jobq` passes (144 s).
- `jobq/check.sh` passes.
- `logstat/check.sh` passes.

**Wall-clock:** about 79 min (4,764 s) from reading the spec to green, measured
with `date`. That figure includes a pause while the machine slept partway
through; the working time is shorter, but I did not measure the pause.

## Loops to green, by cause

A loop is a check, build, or test run that failed. There were 6.

| #   | Check       | Failure                                                                                                                                       | Cause                                                                                                                                                                                                  | First fix worked?                                                                                                                                                                                                                                                                                                                          |
| --- | ----------- | --------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 1   | `go vet`    | `wellFormedJob redeclared`                                                                                                                    | My new function had the same name as an existing test helper                                                                                                                                           | Yes (renamed it `wellFormedFields`)                                                                                                                                                                                                                                                                                                        |
| 2   | `go vet`    | `not enough arguments in call to q.Create`                                                                                                    | The existing tests used the old `Create` and `List` signatures                                                                                                                                         | No. My first regex rewrite ran twice and doubled the arguments (`too many arguments`); a `sed` fix fixed it on the second try                                                                                                                                                                                                              |
| 3   | `go test`   | `TestVerifyCommand`, `TestVerifyCutsATornLastLine`, `TestCheckCommandMatchesExpected`                                                         | Expected: the verify line gained `; archived N` and `/health` gained `"archived"`                                                                                                                      | Yes. I updated the expected strings and regenerated `check.expected`; the only diff was the new field                                                                                                                                                                                                                                      |
| 4   | Simulations | `TestSimulationWithFaults`: ack of an archived job gave 404, the model said 409.<br>`TestSimulationWithRandomBoardFailures`: `j_2 is missing` | Ack/fail looked only at the board.<br>The test builds `BoardConfig` as a literal, so `Retain` was 0 and jobs were archived at once                                                                     | Yes, both. Ack/fail on an archived job now answers 409. `Retain` 0 now means the default, and that test now uses a 1 s retain and looks jobs up in the archive too. The first attempt at this edit applied nothing: a Python assertion failed on a bad anchor and the tests re-ran unchanged. I don't count that as a code fix that failed |
| 5   | Simulations | Full replay: `never failed: a key names two jobs in one queue at once`                                                                        | An open reads the archive before the log, which is not the order the records were written. So an archived job's key was already in the map when an older, deleted job's put with the same key replayed | Yes. The per-record check is gone; the key map is rebuilt, and uniqueness checked, once the open has read both files (`checkApart`)                                                                                                                                                                                                        |
| 6   | `go test`   | `TestHealthNeedsNoToken`, `TestScheduledJobsThroughTheAPI`                                                                                    | Both compare the exact `/health` body, which now has `"archived":0`                                                                                                                                    | Yes                                                                                                                                                                                                                                                                                                                                        |

By cause:

- **Name or signature changes the old tests hit:** 2 (loops 1 and 2).
- **Expected output changed on purpose:** 2 (loops 3 and 6).
- **Real design bugs found by the simulations:** 2 (loops 4 and 5).
- **Where the first fix did not work:** 1 (loop 2, a bad regex).

The new tests in `archive_test.go` and the new `check.sh` section passed on
their first run.

## Design

**Record shape.**

- A job has an optional `key`. The key rule is `validKey`, which uses the same
  rule as queue names.
- A record in the archive also has `archived_at`.
- `key` is shown in every response whenever the job has one.

**The live log.**

- A new record, `{"op":"arch","id":…}`, says the job left the board.
- When the log replays, a put for a job the archive holds, or has tombstoned, is
  out of date and is skipped. The archive's record wins.

**`jobq.archive`.** It uses the same line format as the log, with `put` (an
archived job) and `del` (a tombstone). It is created at its first write, so a
folder that never archives never gets the file, and a read-only folder still
opens. An open reads the archive first, then the log, both under the log's lock.
A torn last line is cut, as in the log.

**The move.** `archiveStep` is the rule for one job, as a pure function.

- At every look, a heap of the `updated_at` times of done and dead jobs gives
  the jobs that are due.
- All due jobs are appended to the archive in one write and one sync.
- Once that write succeeds, the jobs are archived in memory, whatever happens to
  the log afterwards.
- Their `arch` records go into the next write to the log. They are held in
  `unlogged` until a log write succeeds.
- If the archive write fails, nothing moves, and the next look tries again.
- Every change is on disk before the response that reports it.

**Deleting an archived job.** The tombstone is written to the archive first. The
look's own moves are then written the way a read writes them. So a 503 means
nothing changed, and a 204 means the tombstone is on disk.

**Compact.** It rewrites the log first, without archived jobs, then the archive,
without deleted ones. A kill between the two leaves a folder that opens the same
way.

**The kill between the two writes.** At open, a job in both files is archived
and counted once. `checkApart` enforces that at every open: no job is both on
the board and archived, and no key names two jobs.

**Tests.**

- New in `archive_test.go`:
  - The key rule.
  - A second create in every state: queued, scheduled, leased, done, dead,
    archived, and after a delete.
  - A keyed list, and bad keys.
  - The key map surviving a stop and start, a compaction, and the board's own
    restart.
  - Keys checked at open.
  - `archiveStep`.
  - A look with a fixture clock past `retain_ms`.
  - An open with a job in both files, plus compaction of it and of a tombstone.
  - A kill at every write boundary of a load of short-lived jobs, including the
    gap between the move's two writes. The test asserts that this gap was hit.
  - The move's two writes failing on either side of each other.
  - `verify`, `compact`, and `serve` refusing bad archive records.
  - `--retain-ms`.
- Extended fault simulation (`sim_test.go`): the archive is a second in-memory
  file that fails like the log, with a 1.5 s retain and keyed creates. The model
  knows about keys and the archive. The simulation asserts that it touched an
  archived job, answered a create from the key map, and split the move at least
  once.
- The board's restart simulation now archives too.
- `check.script` and `check.expected` gained a keyed create and an archived
  read, across restarts.
- `check.sh` gained section 7: the served process with `--retain-ms 1000`, a
  keyed create, an archived read, the retry 409, `verify … archived 1`, compact,
  restart, delete, and the key freed.

## Files changed

- `experiments/control-run/go/jobq/job.go`
- `experiments/control-run/go/jobq/queue.go`
- `experiments/control-run/go/jobq/store.go`
- `experiments/control-run/go/jobq/verify.go`
- `experiments/control-run/go/jobq/serve.go`
- `experiments/control-run/go/jobq/board.go`
- `experiments/control-run/go/jobq/api.go`
- `experiments/control-run/go/jobq/main.go`
- `experiments/control-run/go/jobq/check.sh`
- `experiments/control-run/go/jobq/testdata/check.script`
- `experiments/control-run/go/jobq/testdata/check.expected`
- `experiments/control-run/go/jobq/archive_test.go` (new)
- `experiments/control-run/go/jobq/sim_test.go`
- `experiments/control-run/go/jobq/board_test.go`
- `experiments/control-run/go/jobq/api_test.go`
- `experiments/control-run/go/jobq/store_test.go`
- `experiments/control-run/go/jobq/queue_test.go`
- `experiments/control-run/go/jobq/verify_test.go`
- `REPORT-change-4.md`

## Decisions the spec did not cover

1. **Which fields a second create still checks.** The body must still decode,
   and `queue`, `payload`, and `max_tries` must still be present, or the answer
   is `400`. `queue` and `key` must be valid. The other values (`payload`,
   `max_tries`, `delay_ms`, `backoff_ms`) are not checked on a key hit, so a
   create with invalid values for them still answers `200`.
2. **An empty key.** `"key": ""` is `400`, not "no key". `"key": null` means no
   key.
3. **A key lookup can return an archived job.** `GET /jobs?queue=q&key=k`
   returns the job even when it is archived, which matches the idempotent
   create. Every other listing hides archived jobs. The `state` filter still
   applies to a key lookup, and `key` with an empty `queue` is `400`.
4. **Ack and fail on an archived job answer `409`**, as they would have for the
   same done or dead job before it was archived. The spec named only retry
   (`409`), delete (`204`), and get (`200`).
5. **What `/health`'s `archived` counts.** It is the number of archived jobs
   that have not been deleted, counted at open and kept current. It is not the
   number of lines in the file. So a job in both files counts once, and
   tombstones do not count.
6. **The archive record rules.** Only `done` or `dead`. `archived_at` is
   required and must be at or after `updated_at`. All live-record rules also
   apply. A live record with `archived_at` is refused. So are:
   - the same job archived twice;
   - a tombstone for a job the archive does not hold;
   - any op other than `put` or `del` in the archive;
   - an `arch` in the log for a job the archive does not hold.

   Errors are reported as `jobq: <dir>: archive record j_N: <rule>`.

7. **The log's `arch` record carries only the id.** The archive holds the job.
   If the log write fails after the archive write succeeded, the job stays
   archived in memory, because the archive's record wins at open. The `arch`
   records go into the next write the log accepts.
8. **A failed archive write fails no request.** Nothing moves, and the next look
   retries. Only a failed tombstone makes a delete `503`.
9. **When a job is due.** A job is due when `updated_at` is at or before
   `now − retain_ms`. A job a look has just moved to dead has `updated_at` equal
   to now, so it is never archived in that same look.
10. **The archive file is created at its first write**, not at open. So `verify`
    and `serve` do not create it in a folder that never archived. Compact
    rewrites the archive only if the file exists or there are archived jobs, and
    it rewrites the log before the archive.
11. **A tombstone is dropped at the next compaction together with its job.**
    Until then, the id stays blocked from being replayed out of the log.
12. **`key` in stored records.** Keys are optional and checked at open (valid,
    never changing for a job, unique in a queue). Uniqueness is checked once,
    after both files have been read, because an open reads the archive before
    the log. A per-record check falsely refused folders in which a deleted job's
    key had been reused by a job that was later archived.
13. **`BoardConfig.Retain` of 0 means the default of one day.** It is internal,
    so test configs built as literals keep today's behaviour. A queue with no
    archive store never archives; only the unit tests build one of those.
14. **The `verify` line format.** `; archived <a>` is appended after
    `next id j_N`, as the spec says, and `<a>` counts the same way as `/health`.
15. **The `409` message for an archived job** is `conflict: j_N is archived`.
16. **`--retain-ms` values.** It must be written in canonical decimal (no
    leading zeros), from 1000 to 2678400000, and given at most once. Any other
    value is a usage error (exit 2), like the other serve options.
