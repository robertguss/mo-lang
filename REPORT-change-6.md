# jobq change 6 (Python): the maintainer's report

Spec: `mo-wiki/spec/programs/01g-job-queue-change-6.md`. Program: `experiments/control-run/python/jobq/`.

## Wall-clock

59 minutes: from 08:44:23 to 09:43:03 UTC on 18 Sep 2026 (4:44 to 5:43 AM ET). That covers reading the spec to the commit, and includes about 12 minutes of bench runs and about 5 minutes of repeated `check.sh` runs.

## Result

- `uv run ruff check`: all checks passed.
- `uv run mypy` (strict, over src, tests, bench): no issues in 28 files.
- `uv run python -m unittest discover -s tests -t tests`: 361 tests, OK. That is 304 before this change, plus 57 new ones in `tests/test_change6.py`.
- `./check.sh`: ok. It passed 5 runs in a row after the fixes below, each in 25 to 30 s at a load average of 3 to 5.
- `ruff format --check` lists 3 test files (`test_api.py`, `test_jobs.py`, `test_store.py`). They were already unformatted at change 5's commit. I did not reformat them, to keep the diff to this change.

## The two bench runs (the budget)

Command: `uv run jobq bench <fresh dir>`, with the defaults `--jobs 30000 --workers 32`. The change-3 program came from `git archive a35acf8` into a scratch directory and was served by the same command with `--serve-src <that>/experiments/control-run/python/jobq/src`. The bench client is always this change's, so both programs meet the same client. Same VM (4 cores), none of my processes running besides the bench. Other sessions' benches were running on the machine, which is why the load average was 2 to 3.4. Each run's lines, as printed:

```
== c6, load average before: 3.39 4.08 3.12
creates: 30000 in 39.0s = 770/s
pairs, 1 workers: 1570 in 5.0s = 314/s
pairs, 32 workers: 4157 in 10.1s = 413/s
rss after pairs: 83.4 MiB
restart with a 15 MB folder: 0.59s to /health; rss 86.5 MiB
== c3, load average before: 2.67 3.80 3.08
creates: 30000 in 39.3s = 763/s
pairs, 1 workers: 1538 in 5.0s = 307/s
pairs, 32 workers: 4013 in 10.0s = 400/s
rss after pairs: 82.5 MiB
restart with a 14 MB folder: 0.56s to /health; rss 84.4 MiB
```

A second pair, run straight after:

```
== c6, load average before: 2.27 3.49 3.01
creates: 30000 in 42.7s = 703/s
pairs, 1 workers: 1355 in 5.0s = 271/s
pairs, 32 workers: 4096 in 10.1s = 407/s
rss after pairs: 83.0 MiB
restart with a 15 MB folder: 0.58s to /health; rss 86.6 MiB
== c3, load average before: 2.45 3.30 2.98
creates: 30000 in 50.4s = 595/s
pairs, 1 workers: 1300 in 5.0s = 260/s
pairs, 32 workers: 3218 in 10.1s = 320/s
rss after pairs: 82.0 MiB
restart with a 13 MB folder: 0.84s to /health; rss 84.2 MiB
```

**Budget: met.** In the first pair, change 6 against change 3 is 770/763 = **1.01×** on creates and 413/400 = **1.03×** on pairs at 32 workers. The floor is 0.8×. The second pair is above 1× on both.

**What the budget made me change:** nothing in the service. Before this change I ran a probe with the same bench against the change-5 program: 470 creates/s and 248 pairs/s at 32 workers, against change 3's 557 and 270, at a load average of 4.5. That is 0.84× and 0.92×, inside the budget and within the machine's noise. This Python program's throughput is bound by fsync: one fsync per create and two per pair. Change 4 and change 5 added only work of O(1) or O(jobs touched) per request: the `_finished` heap, the key map, and invariants checked only on the jobs a change touched. So there was no postcondition walking every job to remove. The bench itself (`jobq bench`, `src/jobq/benchmark.py`) is new.

## Loops to green, by cause

Every run that failed, what it said, and whether the next edit fixed it:

1. **ruff**, after the first source edits: 6 findings (E501, import order, PLR0912 on `Api._match`, PLR0917 on `Queue.__init__`). The first fix (`ruff --fix` and `ruff format`) left 2 of them, PLR0912 and PLR0917. The second fix, a `noqa` with a reason on each, worked. **2 loops; the first fix did not fully work.**
2. **unittest**: `test_change5.RenameTest.test_a_rename_is_one_durable_record` expected the old rename record, without `next_id`. The spec changes that shape, so I updated the test's expected line. **The first fix worked.**
3. **unittest**: the first run of `test_change6` had 11 failures, all mistakes in the new tests. There were four kinds:
   - clock arithmetic: 3 tests pruned at the moment of archiving, and the background test miscounted the minute;
   - a queue collision in one test;
   - my expected error texts did not carry pydantic's `prune.` and `rename.` location prefix (3 tests);
   - the compaction failure was injected into an fsync that the open already runs.

   The same run had 5 ruff findings in the test file (B023 ×3, RUF059, S108). **The first fix worked.**
4. **mypy**: 2 errors ("object" is not iterable) in `test_change6`. **The first fix worked.**
5. **ruff** on the new `checks/sequence.py`: 7 findings (RUF005, E501 ×6). **The first fix worked.**
6. **check.sh**: `head: cannot open .../serve.err`. This race was already there before change 6: `head` can read the file before the background `serve` creates it. Fixed with `2> /dev/null || true`. **The first fix worked** (not seen again in 11 runs).
7. **check.sh**: `-serve exited 0 / +serve exited 143` in `play_archive`. Also already there: the SIGTERM went to the `timeout` wrapper, which races its forwarding to the service. Fixed by sending the signal to the service process itself, the leaf under `timeout` and `uv`. **The first fix worked** (not seen again in 6 runs).
8. **check.sh**: `verify` showed `leased 0 … dead 1` where `leased 1 … dead 0` was expected, after the first `jobq check`. A 60-second lease ran out while `check` and `verify` ran, at a 15-minute load average of about 21 from other sessions. I made no code change. The next 5 runs at load 3 to 5 were green. **Not a code loop; it depends on the load.**

Not counted as a loop: `unittest test_change5` run from the wrong directory once (an import error), and a `ResourceWarning` for the bench's stderr pipe (a warning, not a failure). The pipe is now closed in `Served.stop`.

**Totals:** 9 failed runs.
- 6 were caused by this change's code or tests (causes 1–5), and 5 of those were fixed by the first edit.
- 3 were check-script races that were already there before this change (causes 6–8). Two were fixed by the first edit; one depended on the load and needed no edit.

## Files changed

- `src/jobq/store.py`:
  - `PruneRecord`;
  - `RenameRecord.next_id`;
  - a `prunes` count on archive puts and on the counter;
  - the prune applied in order at replay;
  - `renamed_queue` and `pruned_by`;
  - new open refusals;
  - compaction folds prunes.
- `src/jobq/queue.py`:
  - `prune_step` (pure, with `requires`, `ensures` and `never` checks);
  - `Queue.prune`;
  - the background prune in `expire_due`;
  - `archive_info`;
  - renames write `next_id`;
  - `prune_folder` for `jobq prune`.
- `src/jobq/api.py`: `GET /archive` and `POST /archive/prune`.
- `src/jobq/jobs.py`: `PruneRequest`, `PruneOut`, `ArchiveOut`, `MIN_PRUNE_AGE_MS`.
- `src/jobq/board.py`: `BoardOptions.retention_ms`.
- `src/jobq/cli.py`: `serve --retention`, `jobq prune`, `jobq bench`, and a shared flag parser.
- `src/jobq/benchmark.py` (new): `jobq bench`.
- `checks/sequence.py` (new): the spec's sequence, with every expected answer in it.
- `check.sh`: runs the sequence on a fresh folder and on the change-5 folder, and runs `jobq prune`; fixes the two races that were already there.
- `tests/test_change6.py` (new, 57 tests).
- `tests/test_change5.py`: the rename record's expected line.
- `tests/fixtures/change5/` (new): `jobs.log` and `jobq.archive`, written by the change-5 program.

## The bug report, checked against this program

I ran the change-5 Python program (`a06375d`, from the history) through the reported sequence: jobs archived, `compact`, one more rename, a create into the old name, one more archive, stop. It reopened, and its own `verify` exited 0 (`3 jobs … archived 3`). **The Python program did not have the generation-five bug.** Its archive puts carried a `renames` count, which compaction carried on in the counter record.

The saved folder is `tests/fixtures/change5`. It holds a rename record without `next_id`, archive puts written before and after that rename, and a job created into the old name after the rename. Change 6 opens it with every job in the right queue (`Change5FolderTest`). The sequence then runs on a copy of it in `check.sh`.

**Did the change-5 program write rename records without `next_id`?** Yes, every one. **What was done about them:** they are read as they are and not rewritten; compaction folds them away. A rename without `next_id` is bounded only by its place in the log and the archive put's `renames` count. On any folder the change-5 program wrote, that is the same as the spec's reading ("every job with an id below the highest id at that point"), because every job at that point is numbered below the counter.

## Every declared error, and the test that reaches it

All are in `tests/test_change6.py::DeclaredErrorTest` unless another test is named. Every refusal test also checks that `jobq verify` exits 1 with the same message.

| Declared error | Raised as | Test |
|---|---|---|
| A missing folder | `StoreOpenError` | `test_a_missing_folder`; `check.sh` (`serve` on a missing folder exits 1) |
| A folder in use by another jobq | `StoreOpenError` | `test_a_folder_in_use`; `OfflinePruneTest.test_it_refuses_…` |
| A bad record (not JSON, wrong shape) | `IllFormed` | `test_a_bad_record` |
| A record breaking a job rule | `IllFormed` | `test_a_record_breaking_a_job_rule`; `check.sh` (the ill-formed fixture) |
| A bad archive record | `IllFormed` | `test_a_bad_archive_record` |
| A rename record with a bad name | `IllFormed` | `test_a_rename_record_with_a_bad_name` |
| A rename record to its own name (new) | `IllFormed` | `test_a_rename_record_to_its_own_name` |
| A rename record with a bad `next_id` (below 1) | `IllFormed` | `test_a_rename_record_with_a_bad_next_id` |
| A rename record with `next_id` past the counter (new) | `IllFormed` | `test_a_rename_record_with_next_id_past_the_counter` |
| An archive put past the log's renames | `IllFormed` | `test_an_archive_record_past_the_logs_renames` |
| A prune record with a bad cutoff (negative, a float, a string) | `IllFormed` | `test_a_prune_record_with_a_bad_cutoff` |
| A prune record with a bad count (below 1) | `IllFormed` | `test_a_prune_record_with_a_bad_count` |
| A prune record that takes more archived jobs than its count | `IllFormed` | `test_a_prune_record_taking_more_than_its_count` |
| An archive put past the log's prunes | `IllFormed` | `test_an_archive_record_past_the_logs_prunes` |
| A key clash (one key names two jobs in a queue) | `IllFormed` | `test_a_key_clash` |
| A full disk (ENOSPC) | `StoreError`, 503 | `test_a_full_disk` |
| A write that fails (EIO) | `StoreError`, 503 | `test_a_write_that_fails`; `PruneTest.test_a_failed_prune_write_removes_nothing` (the 503, and nothing pruned) |
| A compaction that cannot write | `StoreOpenError` | `test_a_compaction_that_cannot_write` |
| The bench's service does not start or answers wrongly | `BenchError`, exit 1 | `BenchErrorTest.test_a_service_that_does_not_start_fails_the_bench` |

No declared error was left unreached, so none was removed. Two errors are new in this change: a rename record to its own name, and `next_id` past the counter.

## Nevers and invariants

**Added:**
- `prune_step`: "a prune never removes a live job" and "a prune never removes an archived job younger than its age". Its ensures: every removed job was archived, the rest of the archive stays, the removed jobs' keys are free, and every other key is as it was.
- `Queue.prune`: "a pruned job never comes back".
- `Queue.rename`: "a rename never moves a job created after it".
- At open: a prune record never takes more jobs than its count.

**Changed:** none of the earlier ones.

**Tripped during the work:** none unexpectedly. "Never removes a live job" trips only in its own test, on purpose (`PruneStepTest.test_a_live_job_is_never_removed`).

## Decisions the spec did not cover

1. **Which archive puts a prune applies to is decided by a count, not by the clock alone.** Each archive put now carries `prunes`, the number of prune records the live log held when the put was written, the same way it already carried `renames`. A prune takes only puts written before it. So "an archive record written after the prune is not taken" holds even when the clock steps back (`PruneReplayTest.test_an_archive_record_written_after_the_prune_is_not_taken`). The count is left out of the line while it is 0.
2. **Compaction keeps the renames count, and now the prunes count, on the counter record and on every archive put.** The spec says compaction "keeps no rename record and no count". I kept the counts because compaction renames two files. After a kill between the archive's rename and the log's, the new archive has current names and the old log still has its renames. If the count restarted at 0, those renames would be applied again. For example, rename `a`→`b` and then `c`→`a`: a job in `c` that had become `a` would move on to `b`. The rename records themselves are still folded away.
3. **`next_id` is kept together with the `renames` anchor, not in its place.** By itself, `next_id` also mis-moves an archive put written after the renames, in the same `a`→`b`, `c`→`a` case (`RenameNextIdTest.test_a_rename_after_the_archive_write_does_not_move_it_twice`). The rule applied is: a rename moves an archived job only if the rename comes after the put's count and its `next_id` is above the job's id.
4. **A change-5 rename without `next_id` is bounded only by its place in the log.** It is not given a computed `next_id`. On any folder the change-5 program wrote, this reads the same as the spec's "highest id at that point" (see above). It differs only on hand-built folders.
5. **The prune record is `{"kind":"prune","cutoff_ms":c,"count":k}`.** A job is gone when `archived_ms <= cutoff_ms`, where `cutoff_ms = now - older_than_ms`. So an age exactly equal to `older_than_ms` is pruned, and one millisecond younger is kept (`test_a_younger_archived_job_is_kept_to_the_millisecond`).
6. **At open, a prune that takes more jobs than its count refuses the folder; taking fewer is allowed.** "Fewer" is what a compaction cut short between its two renames leaves: the pruned jobs are already gone from the archive, and the old log's prune record is still there.
7. **A prune's write first carries the `archived` marks of jobs whose earlier mark failed to write, in the same fsync.** This way no stale live record of a pruned job is left without a mark. Replay also drops the live record of any job a prune took.
8. **`older_than_ms` on the API has no upper bound.** A huge age removes nothing, so it writes nothing. `--older-than-ms` and `--retention` on the command line take up to 13 digits. `--retention` accepts 0 (never, the default) or at least 1,000.
9. **When the background prune runs.** It runs at the idle look (the 1 s sweep), not on requests. The first one is at the first idle look after a start, then once every 60 s by the queue's own clock. A prune store failure costs only that round.
10. **`jobq prune` changes nothing else in the folder.** It returns no leases and archives no jobs, so its retention cannot differ from the service's. It refuses a folder a service holds (exit 1, "in use"). It prints `jobq: pruned <dir>: pruned K, remaining M`.
11. **`GET /archive` details.** `bytes` is the archive file's size and does not include the live log. It needs a bearer token, like every route except `/health`. So does `POST /archive/prune`. `oldest_archived_at` is shown as `null` when the archive is empty.
12. **`jobq bench` details:**
    - it takes `--serve-src <path>`, which is not in the spec's usage, so the same command can serve the change-3 program;
    - its client copies `measure.py`: 8 producers, queues `q0`–`q3`, keep-alive connections;
    - the 1-worker run is capped at 5 s and the many-worker run at 10 s;
    - a worker whose queue is empty moves on to the next queue;
    - memory is the service process's VmRSS;
    - restart is from process start to the first `/health` 200.
13. **The sequence is a Python script, `checks/sequence.py`, called twice from `check.sh`.** It is not more lines in `expected.txt`, because job ids and times depend on the folder and the clock. The prune age is computed from the two batches' `archived_at` as observed, so the expected counts are fixed.
14. **The kill between a compacted file's rename and the directory's fsync is done from outside the program.** `sequence.py` runs `compact` in a child process whose `os.rename` and `os.fsync` are patched, and the child `os._exit(137)`s at that point. `CompactionKillTest` does the same for the archive's rename and for the log's. The product has no fault hook.
15. **The change-5 fixture was written by the change-5 program itself** (`a06375d`, from the history) with `--retain-ms 1000`, and saved as-is. Its archived jobs are older than both of the sequence's batches, so the sequence expects them to be pruned with the first batch.
16. **Two races in `check.sh` from earlier changes were fixed**, because they failed runs of this change's check under load: the `serve.err` read and the SIGTERM to the `timeout` wrapper. A 60-second lease that runs out at a load average of about 21 was not changed.
