## jobq change 3: complete and green

**Checks at the end:** `uv run ruff check` clean · `uv run mypy` clean (24
files) · `uv run python -m unittest discover -s tests -t tests`: 230 tests OK
(was 205) · `./check.sh` ok (run three times, same result each time).

**Wall-clock:** 9 min 44 s (14:22:35 → 14:32:19 UTC), from the first read of the
change spec to the last check. Writing this report and committing came after
that.

**Bench, outside the loop count:** throughput 2250 / 5448 lease+ack pairs/s at 1
/ 32 workers (was 2198 / 4519 at change 2). With 10,000 leased jobs, `serve` was
listening after 0.16 s. The `/health` body now includes `"restarts": 0`.

### Loops to green, by cause

Six runs failed. None was a bug in the service code. Two were existing tests
whose expected results this spec changes, two were my own tests or lint, and two
were check.sh output I had not yet recorded as expected.

| #   | Check    | Diagnostic                                                                                                                                                                                                                                                                                                                    | First fix worked?                                                     |
| --- | -------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------- |
| 1   | ruff     | PLR0913/PLR0917 `Board.__init__` had 6 arguments; RUF009 `Budget()` call used as a dataclass default in `ServeOptions`                                                                                                                                                                                                        | yes: I folded the budget and the chaos switch into one `BoardOptions` |
| 2   | unittest | 2 failures in `test_api`: `/health` now has `restarts`, and a broken contract now restarts the board instead of costing only its request (the spec changes both)                                                                                                                                                              | yes                                                                   |
| 3   | unittest | `test_sim` seed 0: "the write resumes on its own". My patched `Chaos.fails` was a bound method set on the class, so it got the wrong arguments. The resulting TypeError counted as a board failure on every write. A crashes == restarts assertion I had added was also circular, because `Sim.restart()` builds a new board. | yes                                                                   |
| 4   | ruff     | I001 import order and E501 in the new `test_server` cases                                                                                                                                                                                                                                                                     | yes                                                                   |
| 5   | check.sh | diff: the two `/health` lines in `expected.txt` lacked `"restarts":0` (expected)                                                                                                                                                                                                                                              | yes                                                                   |
| 6   | check.sh | diff: the new chaos section's output was not yet recorded. Reading it showed that the request that spends the budget was told "restarting". I changed that message to "stopping: the restart budget is spent" and recorded the output.                                                                                        | yes                                                                   |

### Files changed

- **New:** `src/jobq/board.py` (the supervised board, the restart budget and
  `BoardOptions`), `tests/test_board.py` (17 tests), `checks/chaos.txt`
- **Source:** `src/jobq/{contract,queue,api,jobs,store,server,cli}.py`
- **Tests:**
  `tests/{support,test_api,test_cli,test_queue,test_server,test_sim}.py`
- **Checks:** `check.sh`, `checks/expected.txt`

### What was built

- **Restart:** `Board` (in `board.py`) wraps the queue and the API. When the
  board fails, it closes the store, replays the log into a fresh queue and
  answers the failing request with 503. The listener answers 503 straight away
  to requests that arrive while it is rebuilding. If the queue thread itself
  dies, a new thread is started and the board is rebuilt on it.
- **Budget:** `--max-restarts K --restart-window S`. On the failure after the
  K-th restart inside S seconds, the service answers 503 and writes nothing
  more. `serve` then stops and exits 70, and `jobq verify` on the folder
  exits 0.
- **Chaos switch:** `--crash-every N` raises `ChaosFailure` in
  `Queue._commit_all` after the append and fsync, and before the change is
  applied to the in-memory board.
- **`/health`:** reports `"restarts": n` since the process started.
- **Tests:**
  - **Board unit tests:** every kind of write counts toward the chaos switch,
    and a look's moves count too. Leases and ids survive a restart. A lease that
    ran out during the restart is returned at the next look. An unexpected error
    in the middle of applying a change restarts the board. The idle look is
    supervised. A store write failure is not a restart. Budget tests cover the
    window, a budget of 0, and a folder that will not reopen.
  - **Socket tests:**
    - `/health` answers 200 within 1 s of a failure on an 80,000-record log, and
      the write is present after `serve` is stopped and started.
    - A spent budget gives exit 70 and the folder reopens.
    - Requests during a rebuild get 503.
    - The queue thread dying.
    - Chaos under load: 16 clients, every status in {200, 201, 204, 409, 503},
      every 201 job present after `serve` is stopped and started.
  - **CLI:** flag parsing, usage errors, and a real `serve` process exiting 70.
  - **Simulation:** board failures injected at random writes (rate 0.05) across
    100 seeds.
  - **check.sh:** plays `checks/chaos.txt` against a real
    `serve --crash-every 3 --max-restarts 1`. It shows `restarts` going 0 → 1,
    `serve exited 70`, and `verify` finding all 4 writes.

### Decisions the spec did not cover

1. **What counts as a board failure.** Any `ContractError` raised in the queue
   (requires included, since the API validates first, so a broken requires is a
   bug) restarts the board. So does any other exception inside a `Queue`
   operation, which the `operation` decorator wraps as `BoardFailure`.
   `StoreError` stays one request's 503 with no restart, as in change 2. An
   unexpected error in the API layer outside the queue stays one request's 503.
2. **Where the rebuild runs.** It runs synchronously on the queue thread, inside
   the touch that failed. Touches already queued behind it are answered by the
   new board. Requests that arrive during the rebuild get 503 from the listener
   without waiting.
3. **Response bodies.**
   - The failing request:
     `503 {"error":"the service is restarting; read the job to learn what happened"}`.
   - The request that spends the budget:
     `503 {"error":"jobq is stopping: the restart budget is spent; read the job to learn what happened"}`.
   - Every request after that until the process exits:
     `503 {"error":"jobq is stopping: the restart budget is spent"}`.
4. **How the budget counts.** It uses a sliding window of restart times on a
   monotonic clock. A failure that finds K restarts in the last S seconds exits
   70 instead of restarting. `--max-restarts 0` is allowed and means the first
   failure exits 70.
5. **Flag ranges.**
   - `--max-restarts`: 0–99999
   - `--restart-window`: 1–99999 whole seconds
   - `--crash-every`: 0–99999

   Flags may come in any order but each only once. A repeated flag, an unknown
   flag, a missing value or a bad value exits 2 (usage). `compact`, `verify`,
   `check` and `client` reject the flags as usage errors.

6. **What the chaos switch counts.** It counts job changes applied: each record,
   so a look that moves 3 jobs counts 3. A batch fails if any change in it lands
   on a multiple of N, and the whole batch is on disk when it does. The count
   lasts for the whole process and restarts do not reset it. A write the store
   refused is not applied, so it does not count.
7. **Where the injected failure is raised.** After the append and fsync, before
   the in-memory apply. The board is stale until the rebuild, so nothing reads
   it in between.
8. **A rebuild that cannot open the folder.** It counts as a restart and is
   tried again after 0.1 s until the budget is spent, then the service exits 70.
   Without the budget, a folder that never reopens would be retried forever.
9. **A dying queue thread.** If the thread's loop ends without being asked to,
   every touch it holds (the one in flight and those waiting) fails with
   `RunnerDied` and is answered 503. A new thread is started and the board is
   rebuilt on it, which counts as a restart. The test injects the death through
   `QueueRunner._settle`.
10. **The idle sweep is supervised like a request.** A failure in the look it
    takes restarts the board.
11. **`uptime_ms` is from process start** and a restart does not reset it.
    `restarts` is the last field in the `/health` JSON.
12. **What exit 70 prints and closes.** `serve` prints
    `jobq: stopped serving <dir>: the restart budget is spent` to stderr. Open
    connections are closed as on a normal stop.
13. **Test plumbing.** `Store.close()` can now be called twice safely, because a
    restart closes the store that the board's own close later closes again.
    `open_queue` is gone: tests build a `Board`, and the test helpers read
    `queue` from the board, so they follow its restarts.
14. **`ServerThread`** (used by `jobq check` and the socket tests) accepts
    `BoardOptions`. `jobq check` passes none, since the spec gives `check` no
    chaos switch.
15. **The simulation's injected failures** fire at random (rate 0.05 per applied
    batch), using a patched `Chaos.fails`, with an effectively unlimited budget.
    Change 2's rule that a 503 changes nothing is relaxed only for a request
    during which the board restarted. That request may also have deleted or
    retried a job. Every other never is still checked after every request,
    including that the board equals the log.
16. **Formatter style kept.** `except (A, B):` keeps its parentheses, although
    `ruff format` for Python 3.14 would remove them. `ruff format` is not one of
    this project's checks, and `tests/test_api.py`, `test_jobs.py` and
    `test_store.py` were already unformatted at HEAD.
