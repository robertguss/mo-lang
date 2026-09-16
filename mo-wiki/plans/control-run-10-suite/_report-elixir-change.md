# `jobq`, change 1: the maintainer's report

Control run 8, the maintenance round, on the Elixir program. A fresh session
was given the finished round 7 `jobq` (`experiments/control-run/elixir/jobq`),
its spec `spec/01-job-queue.md`, the change `spec/01b-job-queue-change.md`, and
the instruction that the tests must pass and the service must keep its
durability. Elixir 1.18.5, OTP 27, on the Linux VM.

## Wall-clock

**16 minutes**, 00:44 to 01:00 UTC on 16 Sep 2026, from the first read of the
spec to the last green `./check.sh`. That includes building the round 7 escript
and having it write the fixture folder before any code was touched, and one
full `mix run bench/bench.exs replay` (a 1M-record log) at the end.

## Loops to green, by cause

Seven diagnostics over five failing runs. **Every one was fixed by the next
edit; nothing needed a second attempt.**

| # | Check | Diagnostic | Cause | First fix worked |
|---|-------|-----------|-------|------------------|
| 1 | `mix compile --warnings-as-errors` after rewriting `job.ex`, `queue.ex`, `router.ex` | — | green first time | — |
| 2 | `mix test`, after the mechanical rename | `Jobq.CheckTest`: the transcript does not match `script/expected.txt` | expected: the transcript had not been regenerated yet | yes |
| 3 | same run | `Jobq.JobTest`: render's key order is `… tries max_tries backoff_ms created_at …`, the test still wanted the old list | the new field in the middle of the fixed order | yes |
| 4 | `mix test test/jobq/old_log_test.exs` | `assert line =~ "\"tries\":"` on `{"next":7}` | the compacted log's counter marker is not a job; the assertion swept it in | yes |
| 5 | same run | `Jobq.Test.Never` crashed: `no match of right hand side value: %{"attempts" => 0, …}` | the never-checker read `record["tries"]` off a log that still carries the old lines | yes — it now reads a count of tries under either name |
| 6 | `mix test test/jobq/durability_test.exs` | `assert dead != []`, both sides `[]` | the fault run failed each job at most once out of three tries, so nothing ever reached `dead` for a retry to take | yes — every fifth job now has one try only |
| 7 | `mix test` (full) | `Jobq.CLITest`: `compact` said `3 job(s)`, the test wanted `2` | the extended check script leaves three live jobs, not two | yes |
| 8 | `mix format --check-formatted` | two test files off the formatter | long `test` headers and a blank line | yes |

Counted by cause: **3 were the change's own new fields or states reaching a
test that had not been told about them** (2, 3, 7), **2 were the change's new
shapes reaching a checker** (4, 5), **1 was a test that no longer proved what
it claimed** (6), **1 was formatting** (8). None was a defect in the service
itself: no run ever showed a wrong status, a lost job, or a broken `never`.

## The checks, at the end

    mix compile --warnings-as-errors   green
    mix dialyzer                       Total errors: 0
    mix credo --strict                 324 mods/funs, found no issues
    mix test                           4 properties, 104 tests, 0 failures
    ./check.sh                         check.sh: ok

`mix format --check-formatted` is green too. 77 tests before the change, 104
after.

## A folder the old program served

Before any code was touched, `mix escript.build` on the round 7 commit built
the escript and a script was played through `jobq check` to write
`test/fixtures/round7/data/jobq.log`: six jobs in the old shape — `attempts`,
`max_attempts`, no `backoff_ms`, no `run_at`, no `scheduled` — one left leased
by `bob`, one left leased by `carol` on its last try, one queued, one done, one
dead with a reason, and one tombstone. `test/fixtures/round7/README.md` says
what stands in it and `fixture.script` is what wrote it. It is committed as a
fixture, in its own commit, before the change.

`test/jobq/old_log_test.exs` opens it with the service as it is now: every job
is there with its state (`j_1` queued again, `j_5` dead, the tombstone still
removing `j_6`, the counter still above it), the service goes on from there
with a lease, an ack and a retry, everything it writes itself is in the new
names, and `compact` leaves a log with no old name in it and every line
carrying `tries`, `max_tries` and `backoff_ms`. A log written by hand in the
old shape opens the same way. Part three of `check.sh` does it again through
the real escript, over a real socket: it copies the folder, compacts it, greps
the log for an old name, and plays the check script against it.

## Files changed

23 files, +1309 −224 against the round 7 commit.

**The service**

- `lib/jobq/job.ex` — `tries`, `max_tries`, `backoff_ms`, `run_at`, the
  `scheduled` state, `delay_ms/1` and `backoff_ms/1`, `state_names/0`,
  `render/1` and `record/1` in the new fixed order, and `from_record/1`
  reading the old names.
- `lib/jobq/queue.ex` — a third index (scheduled by `run_at`), a look in two
  passes, `create/6` with a delay and a backoff, `retry/2`, `after_try/2`
  replacing `give_up_or_requeue/2`, `scheduled` in the health counters.
- `lib/jobq/router.ex` — `POST /jobs/{id}/retry`, `delay_ms` and `backoff_ms`
  on create, `max_tries` required, the state filter's message off
  `Job.state_names/0`.
- `lib/jobq/store.ex` — a paragraph of moduledoc; no code change. The store
  never knew a field name.

**The program-level check**

- `check.sh` — a delayed job, a retry and the scheduled counter through
  `jobq serve`; an assertion that the log the service writes carries no old
  name; and part three, the round 7 folder.
- `script/check.script`, `script/expected.txt` — a delayed job, a backoff, a
  delete of a scheduled job, a retry and its four `409`s, and the refusals of
  `delay_ms`, `backoff_ms` and a body that still says `max_attempts`.

**The tests**

- `test/jobq/old_log_test.exs` — new, 5 tests.
- `test/jobq/queue_test.exs` — a `describe` of 9 tests for the delay, the
  backoff and the retry; the never test's log now carries a `scheduled`, a
  `dead` and a retry.
- `test/jobq/api_test.exs` — the retry route, the delay and backoff fields and
  their refusals, `state=scheduled`, the scheduled health counter, and that a
  body still saying `attempts` is `400`.
- `test/jobq/job_test.exs` — the new ranges, the scheduled render, and a
  `describe` for records the previous version wrote.
- `test/jobq/durability_test.exs` — a scheduled job across a restart; the fault
  run now creates a third of its jobs with a backoff and a fifth with one try,
  and retries the dead ones at the end.
- `test/jobq/property_test.exs` — `backoff_ms` and `run_at` through the store's
  shape, `delay_ms`/`backoff_ms` over the wire, and a property that a delay or
  a backoff the rules refuse never reaches a job.
- `test/support/never.ex` — the never-checker, rewritten for the new
  transitions and for logs that mix the two record shapes.
- `test/jobq/cli_test.exs`, `test/jobq/listener_test.exs`,
  `test/jobq/store_test.exs` — the rename.

**The rest**

- `README.md`, `bench/README.md`, `bench/bench.exs` — the rename, the new
  fields in the usage, the old-log paragraph, and a `backoff` measurement
  beside `expiry`.
- `test/fixtures/round7/` — the fixture, its script, its README.

## What the change forced open, and what it left alone

**Forced open.** The `never` "a job's `attempts` never exceed its
`max_attempts`" is now about `tries` and `max_tries` — the same claim under new
names. "A dead job is never leased" became "a dead job is never leased until it
is retried", which is a real loosening: the checker now allows one move out of
`dead`, to `queued` with `tries` at 0, and refuses every other. The lease
check's "`attempts` one higher" is now "`tries` one higher" and also refuses a
lease straight out of `scheduled`.

**Added.** "A scheduled job is never leased before its `run_at`" is two checks
in the log: no record moves a job from `scheduled` to `leased`, and a record
that queues a job that was scheduled has an `updated_at` at or after the
`run_at` the previous record wrote.

**Left alone.** "A job is never held by two workers at once" — one process
still owns the state and the move from `queued` to `leased` is still atomic
against every other request; nothing about scheduling touches it. "A response
is never sent before its record is durable" is unchanged in shape: the
scheduled-to-queued move is a record in the same batch, committed by the same
`answer/4`, so the move is on the disk before the reply that saw it. "A job is
never lost" is unchanged; it now also holds of a log the old service wrote,
which is what `old_log_test.exs` is for. The listener, the store's batching and
`fsync`, the framing, the torn-line rule and the exit codes were not touched.

## Measured

Same host, after the change. `mix run bench/bench.exs`:

    create, 8 connections            3227/s   (20000 in 6198 ms)
    lease+ack, 1 worker               397/s
    lease+ack, 32 workers            4664/s
    lease expiry to hand-out            1 ms
    backoff run_at to hand-out          1 ms      (new)
    replay of 1,000,000 records      8348 ms, 200 MiB
    start with 10,000 leased jobs     137 ms

The second deadline the change adds costs the same as the first: a `run_at`
that has passed is read at the next look, like a lease, and the lag is the
sweep, not the feature.

## Decisions the change spec did not cover

1. **`backoff_ms` is always in the record and always in the response**, even
   when it is 0 and even for a job created before the change. The spec lists it
   in `{job}` without a "while" clause, unlike `run_at`, so it is not
   conditional; a reader can therefore always tell a job's backoff without
   inferring it from a state. The cost is nine bytes a record.

2. **`run_at` is dropped on any state but `scheduled`.** A record that says
   `"state":"leased"` and also carries a `run_at` is read as a leased job with
   no `run_at`; the field is not kept "in case". A scheduled record *without* an
   integer `run_at` is not a job at all — the log is corrupt at that line and
   the service refuses to open, which is the existing rule for a record that is
   missing a field it needs.

3. **`from_record/1` prefers the new name when a record carries both.** A
   hand-edited line with `tries` and `attempts` both present reads the new one.
   Nothing the service writes can produce such a line.

4. **A record must still say how many tries a job has had, under one name or
   the other.** `backoff_ms` defaults to 0 when absent, but `tries` and
   `max_tries` do not default: a record with neither `tries` nor `attempts` is
   not a job. The spec says the old names are read, not that the fields became
   optional.

5. **The look takes leases first, then scheduled jobs.** The order is
   observable only in the order of the records in a batch. Leases first is safe
   in one direction: a lease that runs out on a job with a backoff becomes
   scheduled at `now + backoff_ms`, which is strictly after `now`, so it can
   never be promoted in the same look; the reverse order would be safe too, but
   this one reads as the life of a job.

6. **`/retry` answers `409 {"error":"job is not dead"}`** for a queued, leased,
   scheduled or done job — one message for all four rather than one naming the
   state it found. The spec gives the status, not the words.

7. **`/retry` takes no body but refuses a body it does not know.** An empty
   body and `{}` are both fine; `{"why":1}` is `400 unknown field 'why'`, the
   same rule `/ack` already had.

8. **`delay_ms` is validated to 0–86,400,000 and `backoff_ms` to 0–3,600,000,
   separately.** The spec gives both ranges but does not say whether a value
   that is a legal delay is a legal backoff; it is not — 86,400,000 is accepted
   as a delay and refused as a backoff, and there is a test that says so.

9. **A request that says `max_attempts` gets `'max_tries' is required`, not
   `unknown field 'max_attempts'`.** The router checks for missing required
   fields before it rejects unknown ones, which is the order it already had.
   Both are `400`, which is what the spec asks.

10. **The state filter's error message is built from `Job.state_names/0`**
    rather than written out, so a state added later cannot leave a stale
    message behind. It reads
    `state must be queued, scheduled, leased, done or dead`.

11. **A retry drops `reason` and keeps `backoff_ms` and `max_tries`.** The spec
    says the retry drops `reason`; it does not say whether the *next* fail of
    the retried job may set a new one. It may — a fail with a reason writes it,
    a fail without one keeps whatever the job has, which is the existing rule.

12. **The fixture is a folder in the test tree, not a scratch directory.**
    `test/fixtures/round7/data` is committed and read-only in practice: every
    test that serves it copies it to a temporary directory first, so a test run
    never mutates the evidence. `check.sh` copies it too.

13. **`Jobq.Test.Never` reads a count of tries under either name.** The
    never-checker is given whole logs, and a log replayed from an old folder
    mixes the two shapes. Teaching the checker both names was the alternative
    to normalising the log before checking it, which would have hidden the very
    thing the round is about.

14. **The fault run gained a shape, not just a rename.** A third of its jobs
    now carry a backoff and a fifth have one try only, so the run drives
    `leased → scheduled`, `scheduled → queued` and `leased → dead` under
    injected write failures, and it retries every dead job at the end and
    drains again. Without that, the `--sim` equivalent would have passed
    without ever touching a transition the change added.

15. **A `backoff` measurement was added to the bench.** The change adds a
    second deadline with the same "never blocks the job for longer than one
    look" claim as a lease; leaving it unmeasured would have left half that
    claim unread. Nothing else in the bench changed but the field names.

16. **The check script's ids shifted, and two shell assertions moved with
    them.** The script now creates five jobs rather than three and leaves three
    live, so `check.sh` expects `3 job(s)` from a compaction of it and
    `< 201 {"id":"j_3"` from the second play on the served folder. Those numbers
    are the script's, not the service's; a later edit to the script moves them
    again.
