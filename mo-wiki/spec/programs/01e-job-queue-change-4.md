# Program 1, change 4: idempotent creates, and old jobs archived out of the log

The fourth change to `jobq`, the erosion round's generation four (direction 43, measurement 3). Written by Claude (Fable) on 16 Sep 2026 after generation three, whose maintainers all made the store restart itself from its log. This change adds state that the log must carry and a restart must rebuild, and a second file beside the log, so it presses on the seams the last change opened: what a restart rebuilds, what compaction keeps, what `verify` checks. Everything in `01-job-queue.md`, `01b-…`, `01c-…`, and `01d-…` still holds unless a line below changes it. The shape is a product ticket: a producer wants to retry a create without making two jobs, and an operator wants the log to stop growing with jobs nobody reads any more.

## What changes, in one screen

1. **Idempotent creates.** `POST /jobs` may carry `"key"`, a string. A second create with the same key in the same queue makes no job and answers `200` with the job as it stands now. The key is part of the record, survives a restart and a compaction, and is freed when its job is deleted.
2. **Old jobs are archived.** A done or dead job whose `updated_at` is older than `retain_ms` is moved out of the live board and the live log into `jobq.archive` in the same folder, at the next look. `/health` counts them. An archived job can still be read by id. `verify` checks the archive too.
3. **`--retain-ms N`** on `serve`, default 86,400,000 (a day), 1,000 to 2,678,400,000 (31 days).

## The key

`key` is optional, 1 to 64 bytes of letters, digits, `-`, and `_`, the queue name's rule; anything else is `400`. A create with a key answers `201` and the job carries `"key"` in every response that shows it. A create with the same key in the same queue, while that job exists in any state (queued, scheduled, leased, done, dead, or archived), answers `200` with that job and changes nothing; the rest of the body is ignored on that second create, since the first one made the job. The same key in another queue is another job. A deleted job frees its key: the next create with it is `201` and a new job. `GET /jobs?queue=<q>&key=<k>` answers `200 {"jobs": [that job]}` or `200 {"jobs": []}`; `key` without `queue` is `400`.

The key map is state the log carries: after a restart of the process, after change 3's self-restart, and after a compaction, a create with a used key is still `200`. A record's `key` is checked at open like every other field.

## The archive

At every look, each done or dead job on the board whose `updated_at` is at least `retain_ms` before now is archived: its record is appended to `jobq.archive` with `"archived_at"` set to now, and the live log records that the job left the board, so the live board no longer holds it and a compaction no longer writes it. Both writes are on disk before the look's answer. `/health` gains `"archived": n`, the number of records in the archive file, counted at open and kept current; `done` and `dead` no longer count archived jobs. `GET /queues` and `GET /jobs` listings never show archived jobs.

`GET /jobs/{id}` on an archived job answers `200` with the record and `"archived_at"`; `POST /jobs/{id}/retry` on it is `409` (`"archived"`); `DELETE /jobs/{id}` on it is `204` and removes it from the archive at the next compaction (a tombstone in the archive until then, or any equivalent the reader can verify). Its key stays used until it is deleted.

The archive is append-only between compactions. `jobq compact <dir>` rewrites the live log without archived jobs and rewrites the archive without deleted ones; `jobq verify <dir>` checks every archive record against the job's rules (only `done` and `dead` may be there, each with `archived_at`), refuses the folder on a bad one the same way as a bad live record, and prints `; archived <a>` at the end of its line. A folder with no archive file is a folder with an empty archive. A torn last line of the archive is cut like the log's.

**The move under a kill.** A kill between the archive's append and the live log's record leaves the job in both files. At open that job is archived: the archive record wins, the live record is stale, and `/health` counts it once. A kill before the append leaves it live, to be archived at the next look. Nothing is lost and nothing is counted twice, whichever write the kill fell between; the hidden suite will kill the service under a load of short-lived jobs with a small `retain_ms` and check both.

## Usage

```
jobq serve <dir> [--port N] [--max-restarts K] [--restart-window S] [--crash-every N] [--retain-ms N]
jobq compact <dir>
jobq verify <dir>
jobq client <host> <port> <token> <method> <path> [<json>]
jobq check <dir> <script>
```

## Nevers

- A key never names two jobs in one queue at once.
- An archived job never comes back to the board.
- A job is never on the live board and in the archive at once after an open.
- A restart, change 3's or a stop and start, never forgets a key or an archived job.
- Everything in the earlier lists still holds.

## Contracts and tests the reader expects to see

The key rule as one function with a test; the second create answered from the map with the first job, tested in every state including archived and after a delete; the map rebuilt by the replay, tested with a log written by the tests and reopened; the archive move as a pure step over the board plus the two writes, tested with a fixture clock past `retain_ms`; the open with a job in both files; `verify` on an archive with a bad record; the `--sim` or equivalent fault run with the move's two writes failing between; the program-level check script extended with a keyed create and an archived read.

## Measured, for the round

The round's page says what is measured. For the maintainer nothing is asked beyond the report: loops to green by cause, wall-clock, files changed, and the numbered list of decisions this page did not cover.
