# jobq (Elixir), change 6

Spec: `mo-wiki/spec/programs/01g-job-queue-change-6.md`. Program:
`experiments/control-run/elixir/jobq/`. Elixir 1.18.5 on OTP 27.3.4 through
mise.

This session continued the work in `REPORT-change-6-wip.md`, which was done on a
Linux VM. Everything here was run again on this machine: a Mac (macOS, Darwin
25.6, 14 cores). Every server, bench, test, and toolchain process ran under
`toolchain/bench/step36/guard.py`.

## State

All of these passed on the Mac:

- `mix format --check-formatted`: ok.
- `mix compile --warnings-as-errors --force`: ok.
- `mix credo --strict`: no issues.
- `mix dialyzer`: 0 errors.
- `mix test`: 5 properties and 209 tests, 0 failures. The last 49 full runs in a
  row passed, including the 8 seeds that had failed before the fix (see loop
  13).
- `sh check.sh`: ok, including section Eight (`sequence fresh: ok`,
  `sequence change5: ok`).
- The budget is met (see "The two bench runs").

## Wall-clock

- **This session:** 09:23 to 10:15 EDT, about 52 min.
- **My predecessor (VM):** about 1 h 55 min of work time, from 08:42 to 12:40
  UTC, less a VM reboot of about 2 h 45 min.
- **Total:** about 2 h 47 min.

## What this session changed

1. **The board rebuild on a small log was slower than change 5's.**
   - My predecessor's parallel replay (`Task.async_stream` over 2,000-line
     chunks) made a small log slower to open. On a 2,101-line log, `Store.open`
     took a median of 12.1 ms against change 5's 8.6 ms. The cost is copying
     every decoded record back from the task.
   - The chaos switch restarts the board on exactly that kind of log. As a
     result, the existing test `restart_test.exs:205` got fewer creates through:
     a median of about 181 alone, against change 5's 208.
   - **Fix:** the replay now reads in the opening process below 20,000 lines
     (`@replay_parallel_from`) and stays parallel above that.
   - After the fix, a small-log open takes 9.3 ms. Chaos-test creates run alone
     were 186 to 220, against change 5's 171 to 214. The 100k-record test still
     opens within its second.
2. **The board rebuild runs at high priority.**
   - The chaos test still failed about 2 runs in 12 in the full suite. Change 5
     fails the same way on this Mac (2 of 15).
   - Each failing run was a seed that ran `restart_test` early, beside many
     other async tests. There, 16 clients spinning on instant `503`s, plus the
     other tests, took the schedulers the rebuild needed. One failing run got
     `503` 1,247 times against 26 creates.
   - **Fix:** `Queue.init` sets `Process.flag(:priority, :high)` for the replay
     and the index build, then restores the old priority before it serves.
   - After the fix, all 8 seeds that had failed passed, and the next 49
     full-suite runs passed.
3. **A flaky new test, `change6_test.exs` "is pruned offline by jobq prune".**
   - `run_cli` joined the captured stderr to stdout. Every async test that
     writes to `:stderr` at the same moment shares that capture.
   - **Fix:** a success (exit 0) is now read by its stdout alone.
4. **`bench` printed `load average before: unknown` on macOS,** because it read
   only `/proc/loadavg`. It now falls back to `sysctl -n vm.loadavg`.

## Files changed (change 6 against change 5, `eb8a219`)

```
README.md, bench/README.md, check.sh
lib/jobq/bench.ex (new), cli.ex, prune.ex (new), queue.ex, rename.ex,
  router.ex, server.ex, store.ex
script/sequence.py (new)
test/fixtures/change5/data/jobq.archive, jobq.log (new)
test/jobq/change5_test.exs, change6_test.exs (new), test/support/never.ex
17 files, 2,125 insertions, 140 deletions
```

This session touched `lib/jobq/bench.ex`, `lib/jobq/queue.ex`,
`lib/jobq/store.ex`, and `test/jobq/change6_test.exs`, and added this report.
All paths are under `experiments/control-run/elixir/jobq/`.

## The two bench runs

- **Command:** `jobq bench <fresh dir>`, with the defaults of 30,000 jobs and 32
  workers.
- **Change 6:** this worktree's escript.
- **Change 3:** built from `git archive 404628b` in a temporary directory, and
  run through the same bench:
  `jobq bench <dir> --serve '<c3>/jobq serve {dir} --port {port}'`.
- **Order:** the runs alternated, and nothing else of mine was running.
- **Load:** this Mac's load average sits at 6 to 8 from the desktop and other
  sessions (WindowServer, XprotectService, and others). It is printed before
  each run.

The lines as printed, first a pair each way:

```
=== run c3 #1 10:06:36
load average before: 6.19 6.00 5.78
up in 0.19 s; rss empty 101.1 MiB
creates/s: 12584 (30000 in 2.38 s, errors 0)
pairs/s at 1 worker(s): 1690 (7504 in 4.44 s, errors 0)
pairs/s at 32 worker(s): 10952 (22496 in 2.05 s, errors 0)
rss after pairs: 150.3 MiB
restart to /health: 1.69 s (a 23 MB folder); rss 189.4 MiB

=== run c6 #1 10:06:47
load average before: 7.12 6.20 5.85
up in 0.18 s; rss empty 104.3 MiB
creates/s: 14032 (30000 in 2.14 s, errors 0)
pairs/s at 1 worker(s): 1639 (7504 in 4.58 s, errors 0)
pairs/s at 32 worker(s): 10687 (22496 in 2.10 s, errors 0)
rss after pairs: 160.0 MiB
restart to /health: 0.41 s (a 23 MB folder); rss 362.8 MiB
```

Every run:

| pair | program | load before    | creates/s | pairs/s at 1 | pairs/s at 32 | rss after pairs | restart to /health |
| ---- | ------- | -------------- | --------- | ------------ | ------------- | --------------- | ------------------ |
| 1    | c3      | 6.19 6.00 5.78 | 12584     | 1690         | 10952         | 150.3 MiB       | 1.69 s             |
| 1    | c6      | 7.12 6.20 5.85 | 14032     | 1639         | 10687         | 160.0 MiB       | 0.41 s             |
| 2    | c3      | 8.12 6.44 5.94 | 14514     | 1626         | 10056         | 151.4 MiB       | 1.80 s             |
| 2    | c6      | 8.77 6.62 6.01 | 10909     | 1690         | 10692         | 159.4 MiB       | 0.41 s             |
| 3    | c6      | 7.03 6.37 5.94 | 13489     | 1606         | 10682         | 158.8 MiB       | 0.43 s             |
| 3    | c3      | 7.91 6.57 6.01 | 13993     | 1723         | 11322         | 154.5 MiB       | 1.75 s             |
| 4    | c6      | 7.39 6.50 5.99 | 13038     | 1737         | 10931         | 169.1 MiB       | 0.40 s             |
| 4    | c3      | 7.83 6.62 6.04 | 13863     | 1747         | 11259         | 155.4 MiB       | 1.73 s             |
| 5    | c6      | 7.40 6.57 6.03 | 14313     | 1766         | 10894         | 159.6 MiB       | 0.41 s             |
| 5    | c3      | 8.08 6.73 6.09 | 13960     | 1817         | 11408         | 153.3 MiB       | 1.82 s             |
| 6    | c6      | 8.43 6.84 6.14 | 13921     | 1745         | 10748         | 162.9 MiB       | 0.41 s             |
| 6    | c3      | 7.92 6.78 6.12 | 13787     | 1610         | 10899         | 153.0 MiB       | 1.77 s             |

**The budget is met:**

- **Creates a second:** the median over six runs is 13,705 for change 6 and
  13,912 for change 3, **0.99×**. The per-pair ratios are 1.12, 0.75, 0.96,
  0.94, 1.03, and 1.01.
  - The 0.75 is pair 2. There, change 6's creates took 2.75 s against 2.07 s
    while the load rose to 8.8. The next four pairs, run under the same load,
    are all 0.94 or higher.
  - Creates finish in about 2 s, so one run is easily disturbed.
- **Pairs a second at 32 workers:** the median over six runs is 10,720 against
  11,106, **0.97×**. The per-pair ratios are 0.98, 1.06, 0.94, 0.97, 0.96, and
  0.99.

**What the budget made me change:** nothing in the throughput paths. Both
numbers were at the budget on the VM and are at it here.

Two things are worth noting:

- **Restart is faster, and uses more memory while it runs.** Change 6 restarts
  on a 23 MB folder in 0.41 s against change 3's 1.75 s, because of the parallel
  replay. The restart's RSS is higher, about 340 MiB against about 190 MiB.
- **What the chaos test exposed was board-restart latency on a small log.** The
  parallel replay's copying cost is fixed above (points 1 and 2 under "What this
  session changed"). The bench does not measure it.

My predecessor's VM runs (its runs 11 to 14, change 3 against change 6) are in
`REPORT-change-6-wip.md`.

## Loops, by cause

This continues my predecessor's numbering: its loops 1 to 12 are in
`REPORT-change-6-wip.md`, and their causes are summed in the totals below.

| #   | Cause                    | Diagnostic                                                                                                                          | Did the first fix work?                                                                                                                                                                                |
| --- | ------------------------ | ----------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 12  | Tooling (carried)        | My predecessor's restart probe called `Process.exit(nil, :kill)`.                                                                   | Replaced: I wrote new probes (restart time through the chaos switch, and `Store.open` on a 2,101-line log) rather than fix that one.                                                                   |
| 13  | Tests (existing, loop 2) | `restart_test.exs:205`, `assert length(created) > 100`, left 30 to 97. It failed in 9 of 12 full runs, and in 2 of 15 on change 5.  | **No.** The first fix, a sequential replay below 20,000 lines, brought the median to parity but still failed 2 of 12. The second, the high-priority rebuild, worked: 49 runs in a row passed after it. |
| 14  | Tests (new, flaky)       | `change6_test.exs:390`, match failed on `{0, "pruned 0; remaining 0\n"}`. Another async test's stderr landed in the shared capture. | Yes: a success is read by stdout alone. It did not recur in about 60 full runs.                                                                                                                        |
| 15  | Tooling                  | `no such file or directory: python3 …/guard.py`: zsh does not split a string in a variable.                                         | Yes: a two-line wrapper script in the scratchpad.                                                                                                                                                      |
| 16  | Tooling (probe)          | My `Store.open` probe raised `KeyError key :id` because a reply body is `{:obj, kv}`.                                               | Yes.                                                                                                                                                                                                   |
| 17  | Tooling                  | `mix test $F` ran nothing: zsh again.                                                                                               | Yes: `${=F}`.                                                                                                                                                                                          |
| 18  | Budget                   | Pair 2's creates came out at 0.75× change 3.                                                                                        | Shown to be noise by four more pairs (0.94 to 1.03). No code change.                                                                                                                                   |

**Totals across both sessions:** 18 loops.

| Cause                               | Count | First fix worked?                                 |
| ----------------------------------- | ----- | ------------------------------------------------- |
| Environment or existing-test timing | 4     | 1, 2, 11, and 13; two of them needed a second fix |
| Test compile                        | 1     | Yes                                               |
| Tests (new or updated)              | 4     | Yes                                               |
| Lint (credo)                        | 1     | Yes                                               |
| Dialyzer                            | 1     | Yes                                               |
| Tooling                             | 5     | Yes, except loop 12, whose probe was replaced     |
| Budget noise                        | 2     | No code change                                    |

The 4 new-or-updated test loops are 3, 5, 6, and 14. Loop 4 was a real bug in
the compaction tombstones plus a test's expectation. It counts once, under
tests.

Two numbers:

- **Two loops needed a second fix.** Loop 1 needed the replay speed-up (loop
  11); loop 13 needed the high-priority rebuild.
- **`check.sh` never failed.** It passed on the first run on the VM and on the
  Mac.

**An anomaly I could not attribute.** One batch of 10 full-suite runs, the first
after the high-priority change, reported 5 runs with 1 failure each. My output
filter cut the test names off. Every run after it passed: 49 in a row, including
the 8 seeds that had failed before, and a final batch of 10 that recorded
failure names and had none.

## Every declared error, and the test that reaches it

The declaration is in `Jobq.Store`'s moduledoc. Every error on it is reached by
a test. Two error paths are handled but not declared, because no folder that
opens can make them fail: a `rename` that fails during compaction, and a
directory `fsync` that fails.

| Declared error                                               | Test that reaches it                                                                                                          |
| ------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------- |
| Missing or unreadable file, `{:open, path, reason}`          | `change6_test` "a file in the folder that cannot be read refuses the folder" (`:eisdir`, also through `verify`)               |
| Log line not a JSON object, `{:corrupt, line}`               | `store_test` "a complete line that is not JSON at all is a corrupt log"                                                       |
| `next` marker not above earlier ids, `{:corrupt, line}`      | `store_test` "a counter below an id the log carries refuses the folder"; "a counter that is not a number …"                   |
| Archive line not a JSON object, `{:corrupt_archive, line}`   | `archive_test` "a bad archive record, or a line that is not JSON, refuses the folder"                                         |
| Bad job record, `{:record, key, rule}`                       | `store_test` "a record that is not a job names its key …", "a record in a state its fields do not fit …"; `check.sh` Four     |
| Bad archive record                                           | `archive_test` "a bad archive record, or a line that is not JSON …"; `check.sh` Six                                           |
| Rename record with a bad name                                | `change5_test` "a rename record's rule", "verify refuses a bad rename record …"; `check.sh` Seven                             |
| Rename naming the same queue twice, or a field it lacks      | `change5_test` "a rename record's rule" (and the `verify` loop)                                                               |
| Rename with a bad `next_id`                                  | `change6_test` "a rename record with a bad next_id refuses the folder"                                                        |
| Rename whose target has jobs                                 | `change5_test` "verify refuses a bad rename record …" (`target has no job`)                                                   |
| Prune record with a bad cutoff                               | `change6_test` "a prune record's shape", "prune on a folder that is not one, or that does not open"; `check.sh` Eight         |
| Prune record with a bad count, or a field it lacks           | `change6_test` "a prune record's shape"                                                                                       |
| A key clash (a key naming two jobs of a queue)               | `archive_test` "a folder where a key names two jobs of a queue is refused"                                                    |
| Log or archive that cannot be opened to append at start      | `change6_test` "a log the store cannot open to append stops it at start"                                                      |
| A write or sync that fails                                   | `store_test` "a write that fails tells its waiters, keeps the store, and moves the epoch"; `durability_test` "under faults …" |
| A full disk (`:enospc`)                                      | `change6_test` "a full disk is the batch's 503, and the service goes on off the log"                                          |
| A reload that finds the folder refused                       | `change6_test` "a reload that finds the folder refused stops the queue, and the board past its budget"                        |
| A compaction that cannot write, `{:compact, reason}`         | `change6_test` "a compaction that cannot write leaves the folder as it was" (`:eisdir` and `:eacces`)                         |
| An offline prune that cannot append, `{:open, path, reason}` | `change6_test` "an offline prune that cannot append to the log"                                                               |

No declared error was removed. Every one has a test.

## Nevers and invariants

These are unchanged from `REPORT-change-6-wip.md`:

- **Added to `never.ex`:** a prune record names no job.
- **Added to the folder check at open:** a prune record's shape, and a rename's
  `next_id`.
- **Tested:** every never in the spec.
- **Tripped:** none. This session added no never and tripped none.

## Decisions the spec did not cover

Items 1 to 18 are my predecessor's, kept as they were. Items 19 to 21 are this
session's.

1. **The prune's cutoff is inclusive:** a job goes when
   `archived_at <= now - older_than_ms`.
2. **The prune record format** is `{"prune":cutoff,"count":k}`, with a count of
   at least 1. The count is informational and is not checked against what the
   replay removes.
3. **A prune that removes nothing writes nothing,** for an API call as well as a
   background one.
4. **`older_than_ms` limits:** at most 2^53−1. A string or a float is `400`.
5. **`GET /archive`:**
   - `bytes` is the archive file's size on disk.
   - `oldest_archived_at` is found by scanning the archive.
6. **"Written before the prune record"** is read by log order: the line where
   the log last named the job (its archived word, or its live record when a kill
   cut a move short). A job the log names after the prune is not reached by it.
7. **Compaction appends synced tombstones for pruned jobs first,** so a kill
   between the log's rewrite and the archive's cannot bring them back.
8. **`--retention`:**
   - It is 0 or at least 1,000, otherwise a usage error (exit 2).
   - The background prune takes a look first, then prunes.
   - The 60-second interval is fixed; only tests change it.
9. **`jobq prune`:**
   - It prints `pruned k; remaining m`.
   - It uses the system clock.
   - It takes no lock, like `compact`.
10. **A legacy rename without `next_id`:** "below the highest id at that point"
    is read as the replay's counter, which includes the highest id itself.
    - My change-5 program did write such records.
    - The fixture `test/fixtures/change5/data` was written by the change-5
      escript. It opens, serves, compacts, and prunes, and nothing had to be
      done to it.
11. **A rename's `next_id`** is the queue's counter at the time of the rename.
    The folder check refuses a `next_id` below 1, and doesn't check that it is
    at or below the counter.
12. **The bench:**
    - It is an OS-process server from a command template.
    - It follows `measure.py`: 8 producers, 100-byte payloads, 4 queues, and
      pairs at 1 worker and then at N workers, 10 s each or until the queues are
      empty.
    - RSS is the maximum over the server's process tree.
    - The restart is `SIGTERM`, then the time to a `200` on `/health`.
13. **The compaction kill hook** is the environment variable
    `JOBQ_COMPACT_STOP_AT` (`tombstones`, `log`, or `archive`), which exits 137
    at that point.
14. **Directory fsync** when the store or `jobq prune` creates a file.
15. **The sequence is a Python script** (`script/sequence.py`) rather than a
    `check.script` transcript, because the prune's age is computed from the
    `archived_at` values it reads.
16. **The change-5 fixture** was generated by the change-5 escript built from
    history. The sequence's queues (`alpha`, `beta`, `gamma`) are distinct from
    the fixture's.
17. **Keys:** a pruned job's key is freed only when the key map entry names that
    job.
18. **Replay parallelism** was added to meet an existing test's time limit on
    the VM. It is not a spec requirement.
19. **The parallel replay applies only to logs of 20,000 lines or more.** Below
    that, one process reads the log, because a board restart on a small log is
    what the chaos switch waits on. The threshold was picked from two
    measurements:
    - A 2,101-line open: 12.1 ms parallel against 9.3 ms sequential.
    - The 100k test, which still passes.
20. **The queue rebuilds its board at high process priority**, and restores its
    old priority before it serves.
    - Requests during a rebuild are still `503` at once, as change 3 decided.
    - Only the rebuild is favoured over the clients that retry.
21. **The bench's load average on macOS** comes from `sysctl -n vm.loadavg` when
    `/proc/loadavg` is missing.
