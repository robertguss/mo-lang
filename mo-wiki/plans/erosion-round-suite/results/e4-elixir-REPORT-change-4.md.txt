# jobq, change 4: idempotent creates, and old jobs archived out of the log

The Elixir `jobq` in `experiments/control-run/elixir/jobq/`, changed to
`mo-wiki/spec/programs/01e-job-queue-change-4.md`. Elixir 1.18.5 on OTP 27
through mise.

## Result

Every check is green:

| Check                              | Result                                                                                                                                |
| ---------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| `mix compile --warnings-as-errors` | clean                                                                                                                                 |
| `mix format --check-formatted`     | clean                                                                                                                                 |
| `mix credo --strict`               | no issues                                                                                                                             |
| `mix dialyzer`                     | 0 errors                                                                                                                              |
| `mix test`                         | 4 properties, 161 tests, 0 failures (140 before the change); two full runs back to back were both green                               |
| `./check.sh`                       | ok, including a new section six: keyed create, archive over the real escript, `verify`/`compact` with an archive, bad archive refused |

The service is still durable. A look that archives a job appends the archive
record and then writes the log's `archived` marker. Both are fsynced before any
reply in that batch, and the archive record goes to disk first. A delete of an
archived job writes an archive tombstone before its `204`. A failed batch still
moves the store to a new epoch, and the queue reads the whole folder back,
archive included.

## Wall-clock

78 minutes, from 13:05 to 14:24 EDT on 16 Sep 2026. That includes a pause while
the machine slept mid-task (length unknown) and one run of about 10 minutes that
sat in the background.

## Loops to green, by cause

A loop is a failed check, build, or test run.

| #   | Check                                                   | Diagnostic                                                                                                                                                                                                                                                                                                                                                                                                                                                                   | Next edit fixed it?                                                                                                                                                    |
| --- | ------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 0   | `mix test`, baseline before any edit                    | 1 failure: `restart_test.exs:116`, the 100,000-record restart took 1020 ms against a 1000 ms limit. Timing under async load; the failure predates the change.                                                                                                                                                                                                                                                                                                                | No edit made. It did not recur in any later run.                                                                                                                       |
| 1   | compile (`--warnings-as-errors`)                        | `find/2 is unused` after every lookup moved to `find_any/2`. My server edit script also failed its text match, so none of that batch applied.                                                                                                                                                                                                                                                                                                                                | Yes, first fix.                                                                                                                                                        |
| 2   | `mix test`                                              | 96 failures, one cause: `{:badkey, :archived}` in `Queue.load/2`. The update syntax `%{state \| archived: …}` needs the key to exist already, and the initial map never had it.                                                                                                                                                                                                                                                                                              | Yes, first fix.                                                                                                                                                        |
| 3   | `mix test`                                              | 4 failures. 3 in `old_log_test`: the round-7 fixture's done/dead jobs finished about 5.5 days before the test clock, so the default one-day retention archived them. 1 in `check_test`: `/health` now carries `"archived"`.                                                                                                                                                                                                                                                  | Yes. The old-log tests now pass `retain_ms` of 31 days. `expected.txt` was regenerated after extending the script.                                                     |
| 4   | `mix test`                                              | 2 failures in `cli_test`: `verify` and `compact` counts changed because the extended check script leaves 4 live jobs and 1 archived.                                                                                                                                                                                                                                                                                                                                         | Yes, first fix.                                                                                                                                                        |
| 5   | test compile                                            | New `archive_test.exs` used `^archived` inside the same pattern that binds it.                                                                                                                                                                                                                                                                                                                                                                                               | Yes, first fix.                                                                                                                                                        |
| 6   | `mix test` (new tests)                                  | 6 failures, 4 causes. (a) The load test killed the store 11 times, over the default budget of 5, so the service shut down. (b) Wrong expected id in the key-rebuild test (`j_6`, should be `j_8`). (c) A real bug that predates the change, surfaced by the archive (see decision 9): after a compaction wrote `{"next":3}` and a new job `j_3` was created, the next open refused the log as corrupt. (d) Three CLI tests hit `eaddrnotavail` from the local network stack. | (a), (b), (c): yes, first fix. (d): no edit. It did not recur in the next run, and TIME_WAIT was low when I checked, so I treated it as a transient environment issue. |
| 7   | `mix format --check-formatted` and `mix credo --strict` | Two long lines in `old_log_test.exs`. Credo: `read_archive` nested too deep.                                                                                                                                                                                                                                                                                                                                                                                                 | Yes. Ran `mix format`, and pulled `archive_step/2` out of `read_archive`.                                                                                              |

Totals: 7 failing runs after the change (plus the timing failure in the
baseline), about 12 distinct causes. The first fix worked for every cause I
edited. The only failure I did not fix was the environmental `eaddrnotavail` in
loop 6, which never came back.

Not a loop, but noted: `mix run bench/bench.exs` stops at its memory step on
this machine. The bench reads `/proc/self/status`, which is Linux-only, and this
is macOS; the code predates this change. The throughput, expiry, and backoff
sections ran fine before that step. The spec asks nothing of the bench for this
change.

## Files changed

In `experiments/control-run/elixir/jobq/`:

- `lib/jobq/archive.ex` (**new**): the pure move step, `due?/3` and `move/2`.
- `lib/jobq/job.ex`:
  - the `key` and `archived_at` fields, in both `render` and `record`
  - `key/1`, which shares the queue name's rule
  - `check_archived/1`
  - a live record may not carry `archived_at`
- `lib/jobq/store.ex`:
  - the `jobq.archive` file, and `open/1`, which returns the live jobs, the
    counter, and the archived jobs; `read/1` keeps its old shape
  - new record kinds `:archive`, `:archived`, `:unarchive`; the archive's lines
    are written before the log's
  - the `:between` test fault
  - the archive's torn last line is cut on open
  - compaction rewrites the log first, then the archive
  - duplicate-key check at open
  - fix to the `next` marker check
- `lib/jobq/queue.ex`:
  - the key map and the archived jobs
  - a `finished` index, and the third pass of the look (archive)
  - a keyed create answered from the map
  - get, delete, and retry on archived jobs; a key filter on listings
  - `/health` gains `archived`
  - `load/2` rebuilds everything from the folder, on start and on an epoch
    change
- `lib/jobq/router.ex`: the `key` body field, the `key` query parameter, and
  `400` for `key` without `queue`.
- `lib/jobq/server.ex`: passes `:retain_ms` through.
- `lib/jobq/cli.ex`:
  - the `--retain-ms` flag (1,000 to 2,678,400,000, default 86,400,000)
  - `verify` ends its line with `; archived <a>`
  - the message for a corrupt archive
- `lib/jobq/check.ex`: `@retain-ms N` and `@sleep N` script lines.
- `script/check.script`, `script/expected.txt`: a keyed create, the same key
  again, another queue, lookup by key, archived reads, retry `409`, `/health`,
  and a delete that frees the key.
- `check.sh`: the `verify` lines now end with `; archived N`, plus section six.
- `README.md`: usage, keys, archive, and the module tree.
- Tests:
  - `test/jobq/archive_test.exs` (**new**, 13 tests)
  - `test/jobq/job_test.exs` (key rule, archived record rule)
  - `test/jobq/store_test.exs` (counter after a compaction)
  - `test/jobq/cli_test.exs` (`--retain-ms`, bad archive refused everywhere,
    compact/verify after the script)
  - `test/jobq/old_log_test.exs` (runs with 31-day retention)
  - `test/support/never.ex` (reads the `archived` marker, and flags a job that
    comes back from the archive)

And this report, `REPORT-change-4.md`, at the worktree root.

### What the new tests cover, against the spec's list

| Spec item                                                                                  | Test                                                                                                                                                                                                                                                                                                                                                                                                                               |
| ------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| The key rule as one function                                                               | `Job.key/1`, in `job_test` "the key"                                                                                                                                                                                                                                                                                                                                                                                               |
| Second create answered from the map, in every state, archived included, and after a delete | "a second create with the key answers the first job in every state, and a delete frees it"                                                                                                                                                                                                                                                                                                                                         |
| The map rebuilt by the replay                                                              | A log and an archive written by the test, reopened; then a change-3 restart (queue killed), then stop + compact + start                                                                                                                                                                                                                                                                                                            |
| The archive move as a pure step, with a fixture clock                                      | "the move, as a pure step" (two tests); "a done or dead job past retain_ms leaves the board…" (clock one ms short, then due; both files checked before the answer is read)                                                                                                                                                                                                                                                         |
| The open with a job in both files                                                          | "a job in both files opens archived, counted once" (also: deleted from the archive, it does not come back from the log)                                                                                                                                                                                                                                                                                                            |
| `verify` on an archive with a bad record                                                   | `cli_test` "a bad archive record refuses the folder in verify, serve, and compact"; `archive_test` "the store's archive file"                                                                                                                                                                                                                                                                                                      |
| The fault run with the move's two writes failing between                                   | "the move's two writes cut apart by a failing batch" (`:between`, then a failure before the append); and "under kills and failing batches with a small retain_ms" (200 rounds, `retain_ms` 1, every 7th batch fails between the writes, every 11th before them, the store killed every 17 rounds; then: no id live and archived at once, every 2xx job present, `archived` count matches, `Never.check` passes, keys still answer) |
| The program-level check script                                                             | `script/check.script`, diffed by `check_test` and `check.sh`                                                                                                                                                                                                                                                                                                                                                                       |

## Decisions the spec did not cover

1. **Where the log records a move.** A line `{"id":"j_N","archived":true}`. On
   replay it removes the job from the board the way a tombstone does, and keeps
   the id counter past it.
2. **What "archive record wins" means.** An open treats every id the archive has
   ever named, deleted ones included, as never live again, whatever the log
   says. Without the deleted ones, this sequence would bring a job back from a
   stale live record: a kill between the two writes, then a delete of the
   archived job.
3. **Compaction order.** The log is rewritten first, without any archived id.
   Then the archive is rewritten without deleted jobs. A kill between the two
   therefore never lets the log resurrect a job whose archive record is already
   gone. The `next` counter covers the archive's ids too.
4. **A key lookup on an archived job.** `GET /jobs?queue=q&key=k` answers
   `{"jobs": []}` when the job is archived. I followed "listings never show
   archived jobs" over "answers [that job]". A keyed create still answers `200`
   with the archived job, and `GET /jobs/{id}` still reads it.
5. **What `/health`'s `archived` counts.** Archived jobs that are not deleted,
   which is the same number `verify` prints. An archive tombstone is a "record
   in the archive file" in the literal sense, but I did not count it, so a
   delete lowers the count at once.
6. **Error text.** Retrying an archived job answers `409 {"error":"archived"}`,
   the spec's word verbatim. `key` without `queue` is
   `400 {"error":"key needs a queue"}`. Key rule errors copy the queue rule's
   wording with "key". Ack or fail on an archived job is `409` ("caller does not
   hold a live lease"), as for any job that is not leased, not `404`.
7. **Where `key` and `archived_at` go in a response.** After `reason`, in that
   order, and only when present. So responses for unkeyed, unarchived jobs are
   byte-for-byte what they were.
8. **Duplicate keys at open.** A folder where one key names two jobs of the same
   queue (live or archived) is refused like any bad record:
   `record j_N: the key names another job in its queue`, naming the later id. A
   live record carrying `archived_at` is refused
   (`a live job has no archived_at`). An `archived` marker whose job is not in
   the archive is tolerated, and the job is simply gone, because no sequence of
   this service's writes produces one.
9. **A counter-marker bug that predated this change.** Before: after a
   compaction that wrote `{"next":N}`, the first job created afterwards (`j_N`)
   made the next open refuse the log as corrupt. That required deleting the
   highest-id job; now archiving it does the same, and archiving happens all the
   time. The marker is now checked only against ids written before it. A marker
   of 1 is still refused, since compaction never writes one, so the existing
   store test keeps its meaning. A new store test covers the case.
10. **Archived jobs in memory.** The queue holds archived jobs in memory, to
    serve reads by id and the key map. The archive therefore bounds memory by
    jobs finished within the retention window plus whatever sits there until a
    compaction removes deleted ones. The log file stops growing; the process's
    memory does not shrink until an operator deletes archived jobs.
11. **Which look archives.** The move is the third pass of every look (after
    lease expiry and scheduled promotion), including the idle tick. A job that
    goes dead in a look is not archived in that same look, even with `retain_ms`
    1, because its `updated_at` is `now`. The check is
    `updated_at <= now - retain_ms`, per "at least `retain_ms` before now". As
    with the lease expiries from change 1, the idle tick's move has no request
    waiting on it, so a read can report the move while the tick's batch is still
    being fsynced; a request's own look answers only after both writes.
12. **The `--sim` fault.** The store's test `:fault` now takes `:between` (the
    archive is written, the log's write fails) as well as `true` (fail before
    anything). A batch that fails between the writes is handled like any failed
    batch: `503`, new epoch, reload from the folder. After the reload the job is
    archived.
13. **How the check script sees an archive.** The CLI usage of
    `jobq check <dir> <script>` is unchanged. Instead, script lines
    `@retain-ms N` (applied before the service starts) and `@sleep N` (echoed in
    the transcript) let the check script watch a job move. The script uses a
    retention of 2 s. The work before the sleep takes about 55 ms here, so the
    transcript is stable.
14. **The archive file at start.** The store creates an empty `jobq.archive`
    when it starts, as it does the log, and cuts a torn last line of it.
    `verify` and `compact` treat a missing archive as empty and do not create
    one.
15. **Test changes to existing files.**
    - `old_log_test` runs with 31-day retention, since the fixture's clock is
      days past the fixture's jobs.
    - `cli_test`'s counts after the check script, and the `verify` lines in
      `check.sh`, were updated for the extended script and the new
      `; archived N` suffix.
    - No existing assertion about behaviour from changes 1 to 3 was loosened.
