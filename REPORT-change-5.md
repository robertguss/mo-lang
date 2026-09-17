# jobq change 5: report

Change: `mo-wiki/spec/programs/01f-job-queue-change-5.md` (a lease handed to
another worker, and a queue renamed with jobs in flight), made to
`examples/programs/jobq/`.

## Status: green

- `mo fmt --check`: all seven modules pass.
- `mo test --write` passes for every module:
  - job 36, store 14 (unchanged), board 41, api 14, main 18.
  - queue 23 and server 11, under `--sim 100 --faults 20 --until 0.5`. Server:
    all 11 tests hold under faults. Queue: 12 or 13 of 15 hold under faults,
    depending on the seeds.
  - The queue tests that pass only without faults are the same older ones the
    change 4 report names: "a scheduled job is queued once…", "a queue begun
    again rebuilds…", and sometimes the "seventh write" test rejects. Every new
    process test holds under faults.
- `mo test --sim 100` (the corpus's form) passes for all seven modules.
- `mo check --recipe Recipes.Store.Store jobq/store.mo` passes.
- All seven `# run:` lines match their `.expected` files and exit codes under
  `mo run`. `jobq.expected` was regenerated for the longer session; I read the
  new lines before keeping them.
- Builds:
  - `mo build --tests` of every module prints exactly what `mo test` prints,
    with the same exit code.
  - `mo build main.mo` gives the same stdout, stderr, and exit code as `mo run`
    on all seven runs.
- `restarts.py`: every check holds under both the binary and
  `mo run main.mo --`, including the new `rename_under_kills` scenario. That
  scenario:
  - runs three workers that make keyed jobs, lease them, hand them to each
    other, and ack them; the old holder's ack after a handoff must be 409;
  - runs an operator that keeps renaming the busy queue `q` to a fresh name;
  - SIGKILLs serve 5 times at random, and `verify` must open the folder after
    each kill.
  - Afterwards, every job must be in exactly one queue: the first rename after
    its create that took place. Every key must name its job once in that queue.
  - Every acked job must read done, and every leased job must name one worker:
    the last one it was handed to.
  - `/queues` must sum to `/health`, and a rename must be undone by a rename.
  - `compact` must fold all ~70 rename records away, and every job must be in
    the same queue after it.
- Durability: every change is on disk before its answer.
  - A handoff is one record in the batch.
  - A rename is one record, `SET rename_<n> {"from": …, "to": …}`, and it is
    flushed in a batch of its own (decision 11), so nothing decided after it
    shares its write.
  - Archive records are written before the log's, as before.
- `zig build` and `zig build test` were not run. Every server and test process
  ran under `timeout` (300 s, or 600–900 s for whole-file `--sim` runs and the
  harness). `restarts.py` kills any server past 300 s or 4 GB.

## Wall-clock

About 25 minutes (1,470 s), from the first read of the change page to this
report.

## Loops (failed check, build, or test → cause → did the next edit fix it)

1. `job.mo`: MO0317, a stale `verified:` line. I ran `mo test` without `--write`
   after editing (process slip). Fixed by the next run.
2. `board.mo`: MO0105, a test helper (`busy`) declared after the tests. Moving
   it fixed it.
3. `board.mo`: MO0501 ×4, `for` loops with pure bodies in the new tests.
   Rewriting them with `reduce`/`all?` fixed it.
4. `board.mo`: a failing test, and a test bug. My `busy` board made j_2 dead at
   `start()`, so retention archived it along with j_1. Moving its fails 500 ms
   later fixed it.
5. `api.mo`: a failing test, and a test bug. A raw tab inside a JSON body is not
   JSON, so the error was "the body is not JSON". Escaping it fixed it.
6. `queue.mo`: MO0105, helpers after the tests. Moving them fixed it.
7. `queue.mo` under `--sim`: two new asserts were too narrow. A handoff or an
   ack after a create answered 503 is `Missing`. Adding `Missing` fixed both.
8. `queue.mo` under `--sim`: the new rename fault test passed only without
   faults (test bug). It treated "the first four records" as "the jobs made
   before the rename", but a create answered 503 shifts the numbers. Checking by
   job number fixed it.
9. `main.mo`: MO0105, a helper after the tests (the third time). Moving it fixed
   it.
10. `main.mo` run: MO0317 on `api.mo`, `queue.mo`, and `server.mo`. I had
    renamed a board function (`compacted` → `folded_in`, to avoid a clash with
    `main.mo`'s own `compacted`). Re-writing in dependency order fixed it.
11. `mo fmt --check` failed on six modules (long lines). `mo fmt` fixed it.
12. MO0317 on `main.mo`: I re-wrote it before `server.mo`, which it depends on
    (process slip). Re-writing it last fixed it.
13. `queue.mo`, three diagnostics in one run, after I made a rename its own
    batch: MO0301 (the `update` body was 80 lines), MO0304 (an `if` 4 deep), and
    MO0411 (`reply_to` read after it was moved). The next edit, which moved the
    work into `fn alone`, fixed MO0301 and MO0411 but **not** MO0304.
14. `queue.mo`: MO0303 (`alone` took 7 parameters) and MO0304 again (the `case`
    arm counts as a level). Grouping the call, the time, and the chaos count in
    `Taken`, and splitting the arm into two `if`s, fixed both.

By cause (14 loops):

| Cause                                                   | Loops              | Count |
| ------------------------------------------------------- | ------------------ | ----- |
| Toolchain shape rules the code broke                    | 2, 3, 6, 9, 13, 14 | 6     |
| My test bugs, including asserts too narrow under faults | 4, 5, 7, 8         | 4     |
| Stale `verified:` lines (my process)                    | 1, 10, 12          | 3     |
| Formatting                                              | 11                 | 1     |

Every first fix worked except loop 13's, where MO0304 survived into loop 14. No
failing test was a bug in the program.

One real bug was found by reading the code, not by a failing check. Before loop
13, a rename and an archive move decided after it could share one batch. If the
log then refused that batch, the rename was answered 503 but the moved job's
archive record already carried the new name. Decision 11 fixes this.

`restarts.py` also changed once without a failure. In the binary run, `q`
happened to be empty at the end, so the undo check was skipped. The script now
creates a job in `q` first and checks unconditionally.

## Nevers and invariants

- **Added** in `job.mo`: "a handoff changes a lease's lease_until or a job's
  tries, or leaves the job with no worker" (over `Handed`).
- **Added** in `board.mo`, over `Relabeled`, which is made for each job a rename
  moves:
  - "a rename leaves a job in no queue but its own or the new one, or moves a
    job of another queue";
  - "a rename touches a lease".
- **Kept unchanged**: "a job is held by two workers at once". A handoff replaces
  the job's one `worker`, and the old worker's ack or fail is refused by
  `holds?`, so it never makes a `Settled` beside the new worker's.
- **Changed** (a rule, not a `never` clause): "one record per job under its id".
  - A rename is a record under `rename_<n>`, not under any job, and it changes
    the queue of the job records written before it.
  - Job records written after a rename carry `"renames": n` (decision 7).
- **Tripped during the work**: none of the nevers or invariants tripped except
  where a `test rejects` means them to. The new `requires` (handoff by a
  non-holder, after the lease ran out, to a bad worker; a rename step onto
  itself or onto a queue that holds a job) trip only in their own
  `test rejects`.

## Files changed

- `examples/programs/jobq/job.mo`:
  - `handed_off` with its contracts, and the `Handed` never;
  - `worker?` (a token of at most 128 bytes);
  - `tagged`/`renames_of` (the rename count a record carries);
  - tests and `test rejects`.
- `examples/programs/jobq/board.mo`:
  - `Handoff` and `Rename` commands, and `Renamed` and `Absent` outcomes;
  - `renames` and `moves` on the board;
  - `passed_on`, the handoff decision;
  - `renaming`, and `relabeled`, the rename as a pure step with its contracts;
  - the rename record, and its rules in `ill_formed`;
  - `folded`: renames applied at replay to live and archive records;
  - `rebuilt` over the folded records;
  - `snapshot`/`shelf_snapshot` with the count, the rename records, and tagged
    records, plus `folded_in`;
  - decisions tag their records;
  - the `Relabeled` nevers, and 11 new tests plus 2 `test rejects`.
- `examples/programs/jobq/api.mo`:
  - `POST /jobs/{id}/handoff` and `POST /queues/{name}/rename`, with their
    bodies (`to` only);
  - 200 `{"queue", "moved"}` for a rename, and 404 for a queue with no job;
  - 3 tests.
- `examples/programs/jobq/queue.mo`:
  - a rename is a batch of its own (`renames?`, `pending?`, `alone`, `Taken`);
  - the new outcomes in the worker loop;
  - 3 tests: through the queue and a restart; a rename the log refused, then a
    torn rewrite with renames and the archive; and the fault run with the
    rename's write failing, under leases, keyed creates, and a handoff.
- `examples/programs/jobq/server.mo`: one wire test for both routes and their
  statuses.
- `examples/programs/jobq/main.mo`:
  - `compacted_from` folds renames in three writes;
  - tests: compact on a log with two renames and an archive with an old name; a
    compact cut short after each write; verify on a bad rename record, and on a
    key clash that only a rename creates.
- `examples/programs/jobq/data/session.txt`: 28 lines of handoffs and renames.
  They cover every status, a rename undone, and a freed name and key used again.
- `examples/programs/jobq/jobq.expected`: regenerated (56 lines added, nothing
  else changed).
- `examples/programs/jobq/restarts.py`: the `rename_under_kills` scenario.
- `examples/programs/.mo.ids`: jobq entries only, from `mo test --write`
  (`store.mo`'s entry is unchanged).
- `REPORT-change-5.md`: this report.

`examples/README.md` was not changed. Its entry 77 still describes the program's
first version, since it was reset to that before this change.

## Decisions the spec did not cover

1. **The handoff's `to` rule.** The page says both "a token as the lease's is"
   and "1 to 128 bytes, no whitespace". `to` must pass both: the bearer-token
   rule (`token?`) and at most 128 bytes. Otherwise the new worker could not
   present it as a token. Anything else is
   `400 "to must be a token of 1 to 128 bytes with no space"`.
2. **Strict bodies.** A handoff and a rename take `{"to": …}` and no other
   field; any other field is 400, as a create's body is. An empty body is 400
   "the body is not JSON".
3. **A handoff to oneself** is checked after the lease check, so a stranger
   naming itself is 409. For the holder it is 200 with the job exactly as it
   was: no write, `updated_at` unchanged, and no count for the chaos switch.
4. **`updated_at` on a handoff** is set to now. I read "unchanged apart from
   `updated_at`" as "`updated_at` changes".
5. **Handoff of an archived job** is `409 "j_N is archived"`, as ack and fail
   are. An unknown id is 404. A lease that ran out is put back by the look
   first, so the handoff is 409.
6. **The rename record**:
   - It is `SET rename_<n> {"from": "<name>", "to": "<to>"}` in the live log.
   - `n` is the number of renames so far plus one.
   - No time is recorded.
7. **How replay knows which records came before a rename.** The store replays
   into a map, so line order is lost.
   - Every job record written after the first rename carries `"renames": n`, the
     renames it has already seen. This applies to live records and archive
     records alike.
   - Replay applies, in order, only the rename records numbered above that
     count.
   - The field is written only when `n > 0`, so older folders and every earlier
     transcript are unchanged. The API never shows it.
   - The page's archive rule ("the live log's renames applied to the archive
     record's queue") is implemented this way, not literally. Taken literally, a
     job created into a reused name after a rename and then archived would be
     moved by that earlier rename.
8. **A rename count in the log.** Once a queue has been renamed, the log keeps
   `SET renames <n>`.
   - Compaction then folds the rename records away without the numbering going
     back below the counts records already carry.
   - `verify` refuses a count that is not a number, or one below the highest
     rename record ("the rename count is below rename_N").
9. **`compact` with renames writes three times.**
   1. The log whole, with the rename records.
   2. The archive whole, in current names.
   3. The log whole again, without the rename records.

   A kill between any two writes still opens to the same queues (tested).
   Without renames it writes twice, as before. Its output line is unchanged; "to
   N lines" counts the final log.

10. **The torn-log rewrite in the queue** keeps the rename count and records in
    its snapshot, since the archive is not rewritten there and may still need
    them.
11. **A rename is a batch of its own.** The calls already kept are flushed and
    answered first; then the rename is decided and flushed at once.
    - Otherwise an archive move decided after the rename in the same batch would
      carry the new name to the archive. A log that then refused the batch would
      leave that one job renamed while the rename was answered 503.
    - Through `Serve` a rename was already flushed at once.
12. **Statuses and bodies for a rename.**
    - A `name` with no job in any state: `404 "no such queue <name>"`. A target
      with a job, and `to` equal to `name`: `409 "<to> exists"`.
    - 404 is checked before 409, so renaming an empty queue to itself is 404.
    - A bad `name` in the path is 400, as for a lease; a bad `to` is
      `400 "to must be 1 to 64 letters, digits, - or _"`.
13. **A rename moves the queue's lease order and fresh positions** to the new
    name. Any order or pages the target had left from deleted jobs are dropped
    first, so a create into the freed name, or into the target, starts clean.
14. **`moved`** counts live and archived jobs. Deleted (tombstoned) archived
    jobs are not counted.
15. **`verify`'s rules for rename records.** Refusals are named
    `record rename_N`:
    - "its key is not rename_ and a number";
    - "is not a rename";
    - "its from is not 1 to 64 letters, digits, - or _", and the same for `to`;
    - "it renames X to itself".

    Renames are applied before the key check, so a key that two jobs share only
    after a rename is refused ("its key k is j_M's too"). `verify`'s output line
    is unchanged: it has no per-queue counts to rename.

16. **A rename the log did not take** (503) rolls the board back, and the next
    rename reuses its number. A torn write is rewritten whole with the next
    batch, so no two records share a number.
17. **The chaos switch** counts a rename and a handoff as one write each. A 404
    or 409 rename, and a handoff to oneself, count none.
18. **The harness renames to a fresh name each time.** Renaming back into a busy
    name would only be 409, which the other tests already show.
