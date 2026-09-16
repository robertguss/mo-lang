# jobq change 4: report

Change: `mo-wiki/spec/programs/01e-job-queue-change-4.md` (idempotent creates,
and old jobs archived out of the log), made to `examples/programs/jobq/`.

## Status: green

- `mo fmt --check`: all seven modules pass. At the start, five of them (job,
  board, api, server, main) did not, so they were formatted as part of this
  change.
- `mo test --write` passes for every module: job 31, store 14, board 28, api 11,
  main 15. Queue (20) and server (10) pass under
  `--sim 100 --faults 20 --until 0.5`.
  - Server: all 10 tests hold under faults.
  - Queue: 10 of 13 hold under faults. The 3 that pass only without faults are
    older tests: "a scheduled job is queued once the clock passes…", "a queue
    begun again rebuilds…", and the "seventh write" test rejects. They also
    passed only without faults on the unchanged HEAD program (checked on a copy
    of HEAD, where the same 3 kinds failed). None of them is new or changed by
    this work. Every new process test holds under faults.
- `mo check --recipe Recipes.Store.Store jobq/store.mo` passes.
- All seven `# run:` lines match their `.expected` files and exit codes under
  `mo run`. `jobq.expected` and `jobq-6.expected` were regenerated and their
  diffs reviewed.
- The builds were compared with the interpreter, as the corpus test does:
  - `mo build --tests` of every module prints what `mo test` prints.
  - `mo build main.mo` gives the same stdout, stderr, and exit code as `mo run`
    on all seven runs.
- `restarts.py`: every check holds under both the binary and
  `mo run main.mo --`, including the new `archive_under_kills` scenario.
  - That scenario serves with `--retain-ms 1000`, runs three workers making
    short-lived keyed jobs, and SIGKILLs the server 6 times at random.
  - After each kill, `verify` opens the folder.
  - Every acked job reads by id, and no job is counted twice (the `/health`
    total equals the distinct ids across both files).
  - A create with a used key still answers the first job, and a look after the
    retention archives every done job.
  - In the `mo run` pass, 3 jobs were in both files after the kills, and each
    was counted once.
- Durability: every change is on disk before its answer. Archive changes are
  written before the live log's lines in the same batch, and both before any
  caller is answered. A batch the archive refuses writes nothing to the log.
- `zig build` / `zig build test` were not run, as the brief asked. Every server
  and test process ran under `timeout` (300 s, or 900–1500 s for the harness
  scripts), and `restarts.py` kills any server past 300 s or 4 GB.

## Wall-clock

About 89 minutes (5,320 s from the first read to the report). That includes a
short machine sleep partway through.

## Loops (failed check, build, or test → cause → did the next edit fix it)

1. `job.mo`: MO0317, a stale `verified:` line, because I ran `mo test` without
   `--write` after editing. Fixed by the next run. Process slip.
2. `board.mo`: MO0105, a helper declared after the tests. Moving it fixed it.
3. `board.mo`: two diagnostics in one run. MO0214 (`result` used inside an
   anonymous function in an `ensures`) and MO0314 (a `var` captured by an
   anonymous function). Both fixed by the next edit.
4. `board.mo`: two failing tests, both test bugs. One compared health between
   boards with different start times; the other expected ids "1" to be below
   j_1. Both fixed by the next edit.
5. `api.mo`: MO0212, a one-field variant matched by name in a test pattern.
   Fixed by the next edit.
6. `board.mo`: a failing test fed the rebuild two archive entries under one id,
   which the store cannot produce (test bug). Fixed by the next edit.
7. `queue.mo`: MO0317, the dependency `api.mo` had a stale line after `board.mo`
   changed. Re-writing in dependency order fixed it.
8. `queue.mo` under `--sim`, 5 tests passing only without faults:
   - 2 were my new tests. One did unguarded setup writes under faults; the other
     compared a done-only listing with every record in the store.
   - 3 were the older tests described above, not caused by this change.
   - My two were fixed by the next edit. A rerun first hit MO0317 because I
     again ran without `--write` (process slip), then passed.
9. `main.mo`: MO0102, a `return` inside a one-line case arm. Fixed by the next
   edit, which added a `whole_log` helper.
10. `main.mo`: MO0105, a helper after the tests again. Moving it fixed it.
11. `restarts.py` under `mo run`: `/health`'s archived count (4,057) was above
    the archive file's (3,420). Test bug: the new server's first look archives
    more old jobs after the script read the files. Relaxing the check to `>=`
    fixed it (the total-count check was already exact).

Also fixed before any check failed: `compact` created an empty `jobq.archive` in
`data/compact`, seen in `git status`, so `whole_log` now skips an empty archive
that was empty before. And a quadratic list-membership lookup at open was
replaced by maps.

By cause: toolchain rules the code broke (MO0105 ×2, MO0214+MO0314, MO0212,
MO0102) 5; stale `verified:` lines (my process) 3, counting loop 8's rerun; my
test bugs 3 (loops 4, 6, 11); tests that failed under faults 1 (loop 8, whose
older-test part is not a regression). Every first fix worked; the only rerun
that failed again was loop 8's, and that was the stale-line slip, not the fix.

## Files changed

- `examples/programs/jobq/job.mo`: the `key` and `archived_at` fields, `key?`,
  `archived`, and `archive_broken`; `rule_broken` checks keys and refuses a live
  record carrying `archived_at`.
- `examples/programs/jobq/store.mo`: `open_log`, `blank_log`, and a `base` log
  name, so the archive uses the same store and `reopened` works for both files.
- `examples/programs/jobq/board.mo`: the key map, the archived jobs, the
  done/dead index and retention, and `shelved` (the archive move as a pure
  step). Also `shelved_into`, `shelf_applied`, and tombstones; archive-aware
  `rebuilt`/`ill_formed`, and `Placement` with its never.
- `examples/programs/jobq/api.mo`: `key` on create, `key` on listing (only with
  `queue`), and `"archived"` in `/health`.
- `examples/programs/jobq/queue.mo`: `Logs`, and the three-way flush (archive,
  then log). A refused log keeps the archive's changes on the durable board, and
  a torn archive is rewritten whole. Also `Policy.retain_ms` / `retained`, plus
  the tests.
- `examples/programs/jobq/server.mo`: the archive in the opening, and two wire
  tests (keys; archive after retention).
- `examples/programs/jobq/main.mo`: `--retain-ms`, the `Folder` of both logs,
  `verify`'s `; archived <a>`, archive-aware `compact` and `check`
  (`jobq.check.archive`), and masking of `archived_at`.
- `examples/programs/jobq/data/session.txt`: an archived read and retry, keyed
  creates, key lookups, a bad key, and a delete that frees a key.
- `examples/programs/jobq/data/demo/jobq.archive` (new): one archived dead job,
  `j_7`, with key `weekly-7`.
- `examples/programs/jobq/jobq.expected` and `jobq-6.expected`: regenerated.
- `examples/programs/jobq/restarts.py`: the `archive_under_kills` scenario.
- `examples/programs/.mo.ids`: jobq entries only, from `mo test --write`.
- `examples/README.md`: entry 77 describes change 4.
- `REPORT-change-4.md`: this report.

## Decisions the spec did not cover

1. **Tombstone format.** A deleted archived job's tombstone is the archive line
   `SET j_N deleted`, not a DEL.
   - The archive keeps it until the next compaction.
   - At open, a tombstoned id is dropped from both the archive and the live log,
     so a stale live record of that job cannot come back.
2. **Write order.** Every archive change in a batch (moves and tombstones) goes
   to disk before the live log's lines, and both before any answer.
   - If the archive refuses, nothing goes to the log and every call in the batch
     is 503.
   - If the archive takes the batch and the log refuses, the calls are 503, but
     the durable board takes the archive's changes: a moved job stays archived,
     and a deleted archived job stays deleted. So in that one case a 503 DELETE
     of an archived job did take effect.
3. **What the live log records for a move.** It records `DEL j_N`, the store's
   existing delete line; an archive tombstone never needs a live line.
4. **Archived jobs are kept in memory**, paged like the live jobs, so a read by
   id or key never touches the disk. The log stops growing; memory does not
   shrink.
5. **Key lookups include archived jobs.** `GET /jobs?queue=q&key=k` returns the
   job even when archived (with `archived_at`), matching the create rule "in any
   state (… or archived)". Other `GET /jobs` listings and `/queues` never show
   archived jobs.
   - A `state=` filter still applies to a key lookup.
6. **Archived jobs' other routes.** Ack and fail on an archived job are
   `409 "j_N is archived"`, the same as retry. A DELETE of an already-deleted
   archived job is 404.
7. **The `archived` count** in `/health` and `verify` is the number of archived
   jobs (tombstones excluded), not raw archive lines.
8. **Where `key` appears in JSON.** It comes right after `"queue"`, and only
   when set; `archived_at` comes last. A non-string or badly formed `key` is 400
   with "key must be a string" or "key must be 1 to 64 letters, digits, - or _".
   A `key` without `queue` is 400 "a key is looked up in a queue, so key needs
   queue".
9. **The retention boundary.** A job is archived when
   `now - updated_at >= retain_ms`, checked at every look (any request's
   decision and each idle sweep, including the sweep at start). Board tests may
   use a retention below 1,000 ms; only the CLI flag enforces 1,000 to
   2,678,400,000.
10. **`verify`'s new rules.**
    - Archive records are checked with `archive_broken` and named `archive j_N`.
      An archive state other than done/dead reads as "is not a job", because the
      decoder refuses `archived_at` on any other state.
    - A live record carrying `archived_at` is refused ("a live job has no
      archived_at").
    - Two jobs with the same key in one queue are refused at the second ("its
      key k is j_M's too").
    - The ids counter must stay above archived jobs as well.
11. **`compact` order and output.** It rewrites the live log first, then the
    archive, so every tombstone outlives the stale record it guards.
    - Its output line is unchanged for a folder whose archive is empty or
      missing (the existing `jobq-2.expected` still holds). Otherwise it appends
      ", and <dir>/jobq.archive from A to B".
    - It never creates an empty archive file.
12. **Cut-short files at `serve`.** When either the log or the archive ends in a
    cut-short line, `serve` rewrites both whole before serving.
13. **`jobq check`** writes archive changes to `jobq.check.archive` beside the
    folder's archive and removes it before and after, like `jobq.check.log`. Its
    transcript masks `archived_at` along with the other clock values.
    - Because `check` uses the real clock, `data/demo`'s job `j_1` (done
      2026-09-14) is archived at the first look. The transcript's first
      `/health` and listing now reflect that, and the session reads it as an
      archived job.
14. **A create repeated with a key** is answered from the board after the look's
    sweep, so "the job as it stands now" includes a lease run out or an archive
    move made by that same look. The repeat writes nothing itself, and uses no
    id.
15. **The chaos switch's write count** (`--crash-every`) now counts archive
    changes as writes too.
