# A folder the previous version served

`data/jobq.log` was written by the round 7 `jobq` escript — the finished
program of `spec/01-job-queue.md`, built from the commit before change 1 — by
playing `fixture.script` through `jobq check`. It is the log in the old shape:
`attempts` and `max_attempts`, no `backoff_ms`, no `run_at`, no `scheduled`.

At the end of that run the six jobs it created stand as:

| job   | queue   | state  | attempts | max_attempts | note                        |
|-------|---------|--------|----------|--------------|-----------------------------|
| `j_1` | emails  | leased | 1        | 2            | held by `bob` for an hour   |
| `j_2` | emails  | queued | 0        | 1            |                             |
| `j_3` | reports | done   | 1        | 3            |                             |
| `j_4` | reports | dead   | 1        | 1            | reason `disk full`          |
| `j_5` | alerts  | leased | 1        | 1            | held by `carol` for an hour |
| `j_6` | alerts  | —      | —        | —            | deleted; a tombstone line   |

`test/jobq/old_log_test.exs` opens this folder with the service as it is after
the change: `j_1`'s lease has run out and it is queued again, `j_5`'s has run
out on its last try and it is dead, and `compact` leaves a log with no old name
in it. The folder is a fixture, not a scratch directory: a test that serves it
copies it first.
