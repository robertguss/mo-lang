## jobq change 1 — complete and green

**Checks at the end:** `uv run mypy --strict` clean (22 files) · `uv run ruff check` clean · `uv run python -m unittest discover -s tests -t tests` 173 tests OK (was 114) · `./check.sh` ok.

**Wall-clock:** 15 min 50 s (22:22:14 → 22:38:04 UTC), from first read of the specs to the last commit.

### Loops to green, by cause
Six failing runs in total. check.sh never failed; no failure was a bug in the service.

| # | Check | Diagnostic | First fix worked? |
|---|---|---|---|
| 1 | ruff (src) | E501 `queue.py:56`, the `_RETURNS` frozenset line | yes |
| 2 | ruff | E501 `test_api.py:153`, the health dict after the rename | yes |
| 3 | ruff | E501 ×5 in new tests | **no** — I acted on the truncated tail and fixed only 3 of the 5 |
| 4 | mypy | `test_sim.py:124` incompatible assignment: I reused `old` for a `Job \| None` | yes |
| 5 | unittest | `ScheduleInvariantsTest.test_the_scheduled_count_is_right` got "the queued count is right" — my test broke two counts and `check_all` reaches queued first | yes |
| 6 | ruff | the 2 E501 left over from loop 3 | yes |

### Files changed
- **New:** `tests/fixtures/round7/{jobs.log,script.txt}` (committed *before* any code change, written by the unchanged program), `checks/round7.txt`, `checks/round7-after.txt`
- **Source:** `src/jobq/{jobs,store,queue,api,server}.py`
- **Tests:** `tests/{support,test_jobs,test_queue,test_store,test_api,test_sim,test_cli,test_server}.py`
- **Checks and bench:** `check.sh`, `checks/{first,second,expected}.txt`, `bench/bench.py`

Durability held throughout: every create, lease, ack, fail, delete, retry, lease expiry **and scheduled-to-queued move** is in the log before its response, one fsync per look; the round-7 folder opens, serves, and compacts to a log with no old name (asserted in check.sh and in unit tests).

### Decisions the change spec did not cover
1. **Where the rename lives:** a `field_validator` on `PutRecord.job` (`upgrade_job_fields`) — only the store knows the old names.
2. **A record with `attempts` *and* `tries` is refused** as corrupt rather than silently preferring one.
3. **A missing `backoff_ms` reads as 0 for any put record**, not just old-looking ones; `Job.backoff_ms` itself is required, so internal code must always set it.
4. **Every look queues all due jobs globally**, not only those of the queue being read — a superset of the spec's list, matching how leases already behaved.
5. **The look's clock stamps the move:** a lease that ran out while the service was stopped gets `run_at = look + backoff_ms`, not deadline + backoff.
6. **Due means `run_at <= now`**, mirroring the lease rule that a lease is live to its last millisecond.
7. **Run-out leases and due jobs commit together** in one durable write per look; a refused write rolls both heaps back.
8. **`/retry` ignores a body** if one is sent (as `/ack` does), takes any token, and does not record who retried.
9. **Statuses:** 404 (missing) is checked before 409; the 409 body is `{"error":"the job is not dead"}`.
10. **`JobOut` order:** `backoff_ms` always shown (even 0); `run_at` sits after `updated_at`, before `worker`/`lease_until`/`reason`.
11. **Old names in a request** get pydantic's own `"max_attempts: Extra inputs are not permitted"` 400, not a special "renamed" message.
12. **Contracts opened:** `_LEGAL` gained five edges; fixed fields now include `backoff_ms`; `"queued has tries left"` became `"a queued or scheduled job has tries left"`. **Added:** `"scheduled exactly when it has a backoff"`, `"a retry sets tries to 0"`, `"a scheduled job is never queued before its run_at"` (checked as `after.updated_ms >= before.run_at_ms`, since `check_transition` has no clock), `"run_at exactly while scheduled"`. **Left alone:** the two-workers never, the lease/try counting, durability-before-response.
13. **The fixture had to be created:** the repo carried no old `data/` folder, so I generated one with the unchanged program and committed it before touching code, so it is provably pre-change.
14. **check.sh grew** two more `jobq check` runs on a copy of that folder plus a grep asserting the compacted log holds no old name.
15. **`create` takes `delay_ms`/`backoff_ms` as defaulted keyword arguments**, so existing call sites are unchanged; `delay_ms` is validated but never stored, only `run_at`.
16. **The sim's invariant was opened** from "a done or dead job never changes" to "a done job never changes, and a dead one only by its retry", and it now counts scheduled moves and retries so the assertions fail if those paths stop being exercised.
