# jobq change 4: report

Change: idempotent creates by `key`, and done or dead jobs archived out of the
live log into `jobq.archive` (spec `01e-job-queue-change-4.md`), for the Python
program in `experiments/control-run/python/jobq/`.

## Result

All checks pass:

- `ruff check`: clean.
- `mypy --strict`: clean (25 files).
- Unit tests: 261 pass (230 before the change, plus 31 new ones in
  `tests/test_archive.py`).
- `check.sh`: prints `ok`.
- The fault simulation (100 seeds) now also runs keyed creates, `retain_ms` =
  1000, and board failures between the archive write and the log write.

`ruff format --check` was already failing before this change: 5 files, because
the formatter wants to rewrite `except (A, B):` in Python 3.14 syntax. I left
those files alone and did not count it as a gate. The one formatting problem I
introduced, in `store.py`, is fixed, so the count is back to the same 5.

**Durability:** every change is on disk before the response that reports it.

- **Archive move:** the archive append (fsync) comes first, then the live log's
  `archived` record. At open the archive wins, so a job left in both files
  counts once.
- **Delete of an archived job:** a live `delete` is written first, then the
  tombstone in the archive.

**Kill run under load:** I ran a separate script outside the repo. It served
with `--retain-ms 1000` and created keyed jobs, leased and acked them, and
repeated old keys. It SIGKILLed the server 8 times (in later runs, 3 times per
run over 3 runs). After each reopen:

- No job was ever both live and archived.
- Every acknowledged key (20,887 in the longest run) was still answered `200`
  with its original job id.
- `/health` counted every job exactly once, and `verify` was clean.

In one early run, the first kill round recorded no requests at all. It did not
happen again in 3 later runs, and no exception was raised. I could not explain
it.

## Wall-clock

About 77 minutes from reading the spec to this report. This includes a pause
while the machine slept. It also includes the baseline `check.sh` run, which
took 14.5 minutes once (probably the sleep); later runs took about 8.5 s.

## Loops to green: 11 failures

| #   | Cause                               | Diagnostic or failing test                                                                               | Did the next edit fix it?         |
| --- | ----------------------------------- | -------------------------------------------------------------------------------------------------------- | --------------------------------- |
| 1   | lint                                | ruff PLR0913/PLR0917 (`Queue.create` has 6 args); E501 in the `store.py` docstring                       | yes                               |
| 2   | expected output changed by the spec | 4 tests: verify's `; archived <a>` suffix, `/health`'s `archived` field                                  | yes                               |
| 3   | bug in my new test code             | sim: `mail's counts are right` (`/queues` was checked against live + archived jobs instead of live only) | yes                               |
| 4   | my test invocation                  | `ModuleNotFoundError: support` (ran the module directly instead of through `discover`)                   | yes                               |
| 5   | behaviour the spec leaves open      | `test_a_bad_key_is_400`: `"key": null` was accepted                                                      | yes (null is now a 400)           |
| 6   | lint/type in tests                  | F401, E501 ×7, PLR0912/PLR0915 in the sim's `verify`, 3 mypy errors (JSON typing)                        | partly: I001 and PLR0912 remained |
| 7   | lint in tests                       | I001, PLR0912 (13 > 12 after moving code into a helper)                                                  | partly: PLR0912 remained          |
| 8   | lint in tests                       | PLR0912                                                                                                  | yes                               |
| 9   | expected output changed by the spec | `check.sh` diff: new `archived` fields and the new keyed/archive transcript (reviewed, then accepted)    | yes                               |
| 10  | bug in my kill-run script           | `OSError: Can't assign requested address` (one connection per call used up the local ports)              | yes                               |
| 11  | formatting                          | `ruff format`: the `Store.__init__` signature in `store.py`                                              | yes                               |

**By cause:**

- Lint, type and format: 5 (#1, 6, 7, 8, 11). The first fix worked in 3 of
  the 5.
- Expected output changed by the spec: 2 (#2, 9). The first fix worked in both.
- Bugs in my test or harness code, or my invocation: 3 (#3, 4, 10). The first
  fix worked in all 3.
- Behaviour the spec leaves open: 1 (#5). The first fix worked.
- No failures came from the product code's own logic.

## Files changed

All under `experiments/control-run/python/jobq/`:

- `src/jobq/store.py`:
  - Adds the `jobq.archive` file, `ArchivedRecord`, and a `LogFile` class.
  - The rule applied at open (`resolve`): the archive wins, and one key never
    names two jobs.
  - Archive replay and torn-line cutting, record checks for both files, the key
    map, and compaction of both files.
- `src/jobq/jobs.py`: the `key_problem` rule, `Job.key` and `Job.archived_ms`,
  `key` on create and list requests, `key` and `archived_at` in job responses,
  `archived` in `Health`, and the retention bounds.
- `src/jobq/queue.py`:
  - `archive_step`, a pure function, and `_archive_due`, which does the two
    writes.
  - The key map, `keyed`, archived reads, 409 for archived jobs, delete of an
    archived job, and the invariants.
- `src/jobq/board.py`: `BoardOptions.retain_ms`, passed to the queue.
- `src/jobq/api.py`: a keyed create answers `200` from the map,
  `GET /jobs?queue&key`, `key` without `queue` is a 400, and `/health` reports
  `archived`.
- `src/jobq/cli.py`: `--retain-ms`, and verify prints `; archived <a>`.
- `tests/test_archive.py`: new, 31 tests.
- `tests/test_sim.py`: keyed creates, `retain_ms` = 1000, checks over live and
  archived jobs together, and archive/key checks.
- `tests/test_api.py`, `tests/test_cli.py`: expected output updated for the new
  fields.
- `check.sh`: new `play_archive` step (serve with `--retain-ms 1000`, `sleep`
  lines, then SIGTERM), plus compact and verify.
- `checks/archive-first.txt`, `checks/archive-second.txt`: new;
  `checks/expected.txt` updated.

## Decisions the spec did not cover

1. **Record formats:**
   - In the live log, an archive move is recorded as
     `{"kind":"archived","number":n}`.
   - The archive holds `put` records whose job carries `archived_ms` (shown as
     `archived_at`), plus `{"kind":"delete","number":n}` tombstones.
2. **Live write fails after the archive write succeeded:** the move stands,
   since the archive wins at open. The look does not fail. The missing
   `archived` records are written again at later looks.
3. **`--crash-every` and moves:** it counts archive moves as changes, and its
   failure comes between the archive write and the log write, which rehearses
   the kill the spec describes.
4. **Deleting an archived job:** a live `delete` is written before the archive
   tombstone. That way a stale live `put` (from a kill between the two writes of
   the move) can never bring the job back once the tombstone or compaction
   removes it from the archive.
5. **What `/health`'s `archived` counts:** the archived jobs that are not
   deleted, counted after the open's rule is applied. It does not count raw
   lines in the file, so a job in both files and a tombstoned job are each
   handled correctly. Verify's `; archived <a>` uses the same number.
6. **Key lookup and archived jobs:** `GET /jobs?queue=q&key=k` returns the job
   even when it is archived (with `archived_at`), matching the create's `200`.
   Plain listings and `/queues` never show archived jobs. A `state` filter given
   with `key` also applies.
7. **Other actions on an archived job:**
   - `ack` and `fail` answer `409` with the usual "does not hold a live lease"
     message.
   - `retry` answers `409 {"error":"archived"}`.
   - An unknown id stays `404`.
8. **`"key": null`** is a `400` ("key must be a string"), consistent with the
   other optional fields, which also refuse null.
9. **Field order in job JSON:** `key` comes after `reason`, and `archived_at`
   comes last.
10. **Keys never change:** `key` is fixed like `queue` and `payload` (no
    transition changes it), so a retried job keeps its key.
11. **Two jobs with one key at open:** the folder is refused, with
    `record j_m: key 'k' also names j_n in q`.
12. **Refusal messages:**
    - A live record carrying `archived_ms` is refused ("a live job has no
      archived_at").
    - Archive refusals begin with `archive record j_n:`.
    - The archive rules are: only done or dead jobs, and each must have an
      `archived_at`.
13. **Memory:** the whole archive is kept in memory, so reads by id and the key
    map are answered without touching the file.
14. **Missing archive file:** open creates an empty `jobq.archive`, as it
    already creates `jobs.log`. The lock-free `replay` treats a missing file as
    empty.
15. **Compaction:** `compact` rewrites the archive first, then the live log. Its
    output line still counts live records only.
16. **`--retain-ms` values:** it takes up to 10 digits within 1,000 to
    2,678,400,000. Anything else is a usage error (exit 2).
17. **Retention after a retry:** retention runs from `updated_at`. A retried
    dead job gets a new `updated_at` when it finishes again, so its clock
    restarts.
18. **Finding jobs due for archiving:** the queue keeps a heap of
    `(updated_ms, number)` for done and dead jobs rather than scanning the board
    at every look. The pure `archive_step` filters the candidates it is given.
19. **Keyed create:** answered by a lookup (`keyed`) followed by `create`, in
    the same board touch. `create` requires that the key is unused.
20. **Program-level check:** it uses `jobq serve --retain-ms 1000` driven by
    `jobq client`, with `sleep` lines in the script. I did not give `jobq check`
    a `--retain-ms` flag, since the usage in the spec has none.
21. **Pre-existing format failure:** `ruff format --check` was already failing
    on 5 files before this change and still is. I left it alone.
