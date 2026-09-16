## jobq change 2 — complete and green

**Checks at the end:** `uv run ruff check` clean · `uv run mypy` clean (22 files) · `uv run python -m unittest discover -s tests -t tests` 205 tests OK (was 173) · `./check.sh` ok (run three times, stable).

**Wall-clock:** 18 min 05 s (05:16:13 → 05:34:18 UTC), from the first read of the change spec to the last check.

### Loops to green, by cause
Ten failing runs. None was a bug in the service: eight were my own tests or lint, one was an existing test the new rule made ill-formed, one was a wrong assertion I had just written in `check.sh`.

| # | Check | Diagnostic | First fix worked? |
|---|---|---|---|
| 1 | ruff | F401 `server.py`: `StoreError` no longer imported once the broad catch moved to `api.py` | yes |
| 2 | ruff | C420 `cli.py`: `{state: 0 for ...}` should be `dict.fromkeys` | yes |
| 3 | mypy | `server.py`: `add_done_callback` wanted `Future[T]`, `_drop` took `Future[object]` | yes |
| 4 | unittest | 3 failures, 5 errors in `test_store`: the `job()` helper built `done`/`leased` jobs with `tries: 0`, which the new rule refuses, and two tests asserted the old `line 1 is not a record` wording | yes |
| 5 | mypy | `test_jobs.py`: `WELL_FORMED` inferred as `dict[str, dict[str, int]]`, so `\| {"worker": "w1"}` did not type | yes |
| 6 | ruff | E501 ×3 in the new `test_api` cases | yes |
| 7 | ruff + unittest | `test_cli.py` unterminated string: my edit script wrote a real newline where `\n` belonged | yes |
| 8 | ruff | RUF012 mutable class attribute `BODY` in `test_api` | yes |
| 9 | unittest | `VerifyTest` expected `leased 1, done 1` and got `leased 2, done 0`: a lease takes the **oldest** queued job, so my `ack("j_2")` acked nothing | yes |
| 10 | check.sh | "an ill-formed folder was left locked" — my own new assertion was wrong: every open creates `jobq.lock`, refused or not; it now asserts the log is byte-identical instead | yes |

**One regression the bench caught, outside the loop count.** Putting every queue touch on its own thread (needed for the five-second rule) cost **4438 → 1279** lease+ack pairs/s at 32 workers. Taking every waiting touch in one batch instead of one handoff per request restored it: **4519** pairs/s at 32 workers, 2198 at 1 worker (was 2518 — the cost of a single handoff), lease lag median 0.8 ms (was 0.7 ms). `replay` and `restart` unchanged; `memory` needs `/proc` and does not run on this machine, as before.

### Files changed
- **New:** `tests/fixtures/illformed/jobs.log` — a hand-written folder holding one good record and the incident's: `leased` with a `run_at` and no worker.
- **Source:** `src/jobq/{jobs,store,queue,api,server,cli}.py`
- **Tests:** `tests/{test_jobs,test_store,test_api,test_server,test_cli,test_sim}.py`
- **Checks:** `check.sh`, `checks/{first,second,round7,expected}.txt`

Durability held throughout: every change is in the log and fsynced before the response that reports it, a 503 leaves the log as it was, and the simulation checks after **every** request that the store holds exactly what the queue holds — now including a stretch where the folder refuses every write and then takes them again with no restart.

### Decisions the spec did not cover
1. **The record's key.** The log has no key beside its record: a put record's key is the job id its `number` names, so "the record's key names the job's id" holds by construction and cannot be broken. A line that does not decode as a record at all is named `line <n>`.
2. **The rule text for a record that does not decode** is pydantic's first problem with its path, lower-cased: `record j_1: job.attempts extra inputs are not permitted`. The old `jobs.log line 1 is not a record` wording is gone and two existing tests were updated to the new one.
3. **`verify` opens exactly as `serve` does**, exclusive lock included, so it sees what a start would see. It therefore refuses a folder another jobq is serving, leaves the same `jobq.lock` file behind, and cuts a torn last line off as any open does. It never rewrites a record (asserted in `check.sh`).
4. **`verify`'s line prints the next id even for an empty folder** (`0 jobs: ...; next id j_1`).
5. **The counter record was left as change 1 had it:** `next_number` is the max of the counter and every job's number, so a counter below a job's number is lifted rather than refused. The spec said "refused as before", and before was this.
6. **A broken contract is now a 503, not a 500.** The spec makes anything the implementation did not expect a 503; the bug is still printed to stderr, and the simulation's "no request is an internal error" keeps holding.
7. **The 503 bodies:** `{"error": "the request could not be completed"}` for anything unexpected, and the existing `store unavailable: <why>` for a store that could not be written.
8. **The five-second rule needed the queue off the event loop.** A hung fsync cannot be interrupted from the loop, so every queue touch now runs on one `QueueRunner` thread — operations still never interleave, because there is still only one of them at a time. A touch that has not answered in five seconds is a 503 for that request; the touch itself is never abandoned and whatever comes after it waits behind it, so a 503 never leaves a job half changed.
9. **The idle sweep runs through the same thread**, so a sweep and a request can never touch the queue at once.
10. **The store latches nothing any more.** `_broken` (which said "restart jobq" forever) is gone: a roll-back that cannot truncate marks the log dirty, and the next write truncates it first. A store that cannot be written answers 503 to every write, keeps answering reads, and takes the first write that can go through.
11. **The unwritable folder is injected at the `FileOps` boundary** in the tests, because on POSIX a folder made read-only after the log is open does not stop a write — the mode is read when a file is opened. The spec's test does make the folder read-only, and injects the refusal alongside it, with the reason written down in the test.
12. **`/queues` walks the jobs** at each request rather than keeping per-queue counts in step with every change: one fewer thing that can drift, and `/health` keeps using the queue's own counters.
13. **`/queues` takes a token** like every route but `/health`, answers only GET (405 with `allow: GET`), and never lists a queue with all-zero counts — only queues holding a job.
14. **`jobq verify <dir> extra` is a usage error** (exit 2); `verify` takes exactly one argument.
15. **`check.sh`'s `/queues` calls sit after the restart and on the round 7 folder**, not in the first run, where j_2's 100 ms lease makes the live counts race the wall clock. The first run still checks `/queues`' 401 and 405. The script also runs `verify` four times and asserts that `verify`, `serve` and `compact` all refuse the ill-formed folder with exit 1 and the exact line `jobq: <dir>: record j_2: a leased job has no run_at`.
16. **`compact` gained an ensure** that every record it wrote is well-formed.
17. **A connection that fails unexpectedly is logged and closed**, and a failing idle look costs that look only: neither stops the next request.
18. **`job_problem` lives in `jobs.py`**, beside the `Job` model, and takes a decoded `Job` with no preconditions; the store calls it on every put record as the log replays.
