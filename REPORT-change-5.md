# jobq (Elixir), change 5: a lease handed off, and a queue renamed

Spec: `mo-wiki/spec/programs/01f-job-queue-change-5.md`. Program:
`experiments/control-run/elixir/jobq/`. Elixir 1.18.5 on OTP 27.3.4 through
mise.

## Result

All checks pass.

- `mix format --check-formatted`: ok
- `mix compile --warnings-as-errors --force`: ok
- `mix credo --strict`: no issues
- `mix dialyzer`: 0 errors
- `mix test`: 4 properties and 182 tests (161 existing and 21 new), 0 failures.
  Ran 3 times in a row; all 3 passed.
- `sh check.sh`: ok, with a new section Seven and the extended transcript. No
  server processes were left running afterwards.

**Wall-clock:** about 11 minutes, from reading the spec to the final checks, not
counting this report and the commit.

## Loops to green, by cause

There were 5 failures in total. The first fix worked every time.

| #   | Cause                      | Diagnostic                                                                                                                                                                                               | Did the first fix work?                                                                        |
| --- | -------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| 0   | Environment                | `mix compile` stopped with "Unchecked dependencies… run mix deps.get". The fresh worktree had no `deps/`.                                                                                                | Yes: ran `mix deps.get`.                                                                       |
| 1   | Lint (credo)               | `[F] Function body is nested too deep (max depth is 2, was 3)` in `test/jobq/change5_test.exs` `work/3`.                                                                                                 | Yes: moved the inner block into a new function, `hand_on/4`.                                   |
| 2   | Tooling (my shell command) | zsh `no matches found: …/c5/*` in an ad hoc transcript run. This was not a code failure.                                                                                                                 | Yes: used the scratchpad path instead.                                                         |
| 3   | Program check (`check.sh`) | Section Seven failed with `cannot bind port …: address already in use` after `kill -9`. The signal hit the `timeout` wrapper, and the server kept running.                                               | Yes: `pkill -9 -P "$served"` sends it to the server itself. I also killed the orphaned server. |
| 4   | Tests                      | 2 failures in `test/jobq/cli_test.exs`. These tests assert the check script's final counts (`leased 1, done 0 … next id j_9`), and the extended script changes them (`leased 0, done 1 … next id j_10`). | Yes: updated the expected counts and comments.                                                 |

All 21 new tests passed on their first run.

## Which `never`s and invariants changed, and which tripped

- **Changed:** "A job is never held by two workers at once." The log checker
  `test/support/never.ex` used to reject any leased record that followed a
  leased record ("leased while already leased"). Every handoff writes exactly
  that pair, so the checker would have failed on every handoff.
  - The checker now allows a leased-after-leased pair only when it is a handoff:
    the worker changed, while `tries` and `lease_until` stayed the same.
  - It still rejects a second leased record with the same worker.
  - It still guarantees one worker per record, so a job never has two workers at
    once.
  - I changed it before writing the handoff tests, so I never saw it trip.
- **Added to the log checker:**
  - A handoff never changes `tries` or `lease_until`.
  - A rename record names no job and moves no state.
- **Added to the folder check at open** (used by `serve`, `verify` and
  `compact`):
  - A rename record's two names must follow the queue-name rule and must differ,
    and the record may have no other fields.
  - A rename's target must have no job on the log at that point in the replay,
    because the service never merges queues.
  - An `archived` record in the log that names a queue must name a valid one.
- **Tripped during the work:** nothing, apart from the diagnostics in the loop
  table above.

## Design in brief

**Handoff** (`Jobq.Handoff.step/4`) is a pure step:

- _requires:_ the job is leased by the caller. The periodic check for expired
  leases runs first, so an expired lease is already gone and the handoff gets
  `409`.
- _ensures:_ only `worker` and `updated_at` change.
- The queue writes the result as one normal job record, so a handoff counts as a
  write for the chaos switch and survives a restart like any other write.

**Rename** (`Jobq.Rename`) is a set of pure functions:

- `check/3`, `jobs/3` and `keys/3` do the work.
- The queue moves its `queued` and `by_queue` rows as a whole. The deadline
  indexes and the counts don't track queue names, so they don't change.
- One record, `{"rename":from,"to":to}`, is written to the log before the
  response.

**Replay** (`Jobq.Store`):

- Applies renames in order to the jobs replayed so far.
- Also tracks the queue of every job the log has moved to the archive, and
  applies later renames to it.
- An archived job's queue is taken from the log while the log still names that
  job. Otherwise it is the archive record's queue with every rename in the log
  applied.

**Compaction:**

- Rewrites the log first. For each archived job whose archive record carries an
  out-of-date name, the new log gets a word
  `{"id":…,"archived":true,"queue":<current>}`.
- Then rewrites the archive with current names.
- If the process is killed between the two rewrites, the folder still opens with
  the same names. A test covers this with the tricky order: rename `b→c`, then
  rename `a→b`.

## Files changed

- `experiments/control-run/elixir/jobq/lib/jobq/handoff.ex` (new)
- `experiments/control-run/elixir/jobq/lib/jobq/rename.ex` (new)
- `experiments/control-run/elixir/jobq/lib/jobq/job.ex`: the `worker/1` name
  rule
- `experiments/control-run/elixir/jobq/lib/jobq/queue.ex`: the `handoff` and
  `rename` operations
- `experiments/control-run/elixir/jobq/lib/jobq/router.ex`: the two routes
- `experiments/control-run/elixir/jobq/lib/jobq/store.ex`: the rename record,
  replay order, archive names, compaction
- `experiments/control-run/elixir/jobq/test/jobq/change5_test.exs` (new, 21
  tests)
- `experiments/control-run/elixir/jobq/test/jobq/cli_test.exs`: counts that
  follow the extended script
- `experiments/control-run/elixir/jobq/test/support/never.ex`: the handoff
  exception, and the rename record
- `experiments/control-run/elixir/jobq/script/check.script` and
  `script/expected.txt`: a handoff and a rename
- `experiments/control-run/elixir/jobq/check.sh`: section Seven, which does a
  handoff and a rename, kills the server with `kill -9`, reopens the folder,
  compacts it, and checks that a bad rename record is refused
- `experiments/control-run/elixir/jobq/README.md`
- `REPORT-change-5.md`

## Decisions the spec did not cover

1. **Where the `to` rule applies.** The rule "1 to 128 bytes, no whitespace"
   applies only to the handoff's `to`, which must also be valid UTF-8. The
   caller's bearer token keeps its old rule (non-empty after trimming), so a
   worker whose token is over 128 bytes can still lease and ack. It just can't
   be named as a handoff target.
2. **Handoff to yourself** writes no record and leaves `updated_at` unchanged,
   which is my reading of "changes nothing".
3. **A real handoff sets `updated_at` to now.** The spec's sentence on
   `updated_at` contradicts itself, so I took "apart from `updated_at`" to mean
   it changes.
4. **Handoff on a job the caller doesn't hold** (queued, scheduled, done, dead,
   archived, or leased by someone else) is `409` with the same message `ack`
   uses. An unknown or malformed id is `404`.
5. **Validation order for a handoff.** A bad body is `400` even for a job that
   doesn't exist, as `fail` already behaves.
6. **A queue whose only jobs are archived can be renamed**, and counts as taken
   when it is the target. This follows "in any state, live or archived", even
   though `GET /queues` doesn't list such a queue. The `404` body is
   `{"error":"no such queue"}`.
7. **Both `409` cases** ("target has jobs" and "`to` equals `name`") return the
   body `{"error":"exists"}`.
8. **Rename permissions and validation order.** Any bearer token may rename,
   since there is no operator role. A bad name in the path is checked before the
   body.
9. **The rename record's format** is `{"rename":<from>,"to":<to>}`. A record
   with any other field is refused at open.
10. **The folder check refuses a merge.** It refuses a rename record whose
    target already has a job on the log at that point in the replay, because the
    service never writes one. It doesn't count archive-only jobs or jobs already
    moved to the archive, since an archived job that was deleted frees its name.
11. **An archived job's queue comes from the log while the log still names it.**
    Read literally, the spec's rule (the log's renames applied to the archive
    record's queue) gives the wrong answer in one case. After a rename `a→b`, a
    new job created in `a` and archived as `a` would become `b` on reopen. So
    when the log still names the job, the log's queue wins, and only the renames
    written after the job left are applied. When the log doesn't name the job
    (because it was compacted away), all the log's renames are applied.
12. **Compaction writes an extra record type** to stay safe if killed between
    its two rewrites. For an archived job whose archive record has an
    out-of-date name, the compacted log gets
    `{"id":…,"archived":true,"queue":<current>}`. It isn't a rename record, it
    is written only for such jobs, and the next compaction doesn't write it
    again.
13. **`moved` counts live and archived jobs.** Deleted jobs aren't counted
    because they are gone.
14. **No key-clash check for renames.** The target must have no jobs, and every
    key belongs to a job, so a clash can't happen. The pure-step test explains
    this.
15. **Rename check cost.** A rename scans the board and the archive, which is
    O(n). Renames are rare, and moving the jobs is O(n) anyway, so I didn't add
    an index per queue for archived jobs.
16. **The new check-script lines go at the end**, so the earlier transcript
    lines are unchanged. The CLI tests that assert the script's final state now
    expect `j_2` done and next id `j_10`. The script runs on `served` and
    `round7` too, where only its first create is asserted.
