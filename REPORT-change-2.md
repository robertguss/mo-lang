# jobq, change 2 — the maintainer's report

The Elixir `jobq` in `experiments/control-run/elixir/jobq/`, changed to
`mo-wiki/spec/programs/01c-job-queue-change-2.md`: the folder is checked at
open, a failing request never takes the service down, and operators get
`GET /queues`.

Elixir 1.18.5 on OTP 27 (erts 15.2.7.13) through `mise`.

## Wall-clock

**About 16 minutes**, 01:18 to 01:34 EDT on 16 Sep 2026, from reading the spec
to the last green run of every check. The single longest step was the first
`mix deps.get` and the dialyzer PLT build (~35 s of it).

## Loops to green, by cause

Ten loops. Nine of the ten were fixed by the next edit; one needed a second.

| #   | Cause                                               | Diagnostic or failing test                                                                                                                                                                                                                                                                                               | First fix worked?                     |
| --- | --------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------- |
| 1   | build                                               | `mix compile`: "Unchecked dependencies for environment dev" — the worktree had never run `mix deps.get`                                                                                                                                                                                                                  | yes (`mix deps.get`)                  |
| 2   | the change's own new contract, met by the old tests | 5 at once: `StoreTest` "the last record of an id wins" / "compact leaves one line per live job" / "a complete line that is not a record" (records the new rule refuses), `StoreTest` "a write that fails takes the store down" (`Store.commit/4` is now `/5`), `ApiTest` "a route that is not there is 404" on `/queues` | yes for 4 of the 5; the 5th is loop 3 |
| 3   | implementation defect, caught by a new test         | `StoreTest` "a counter below an id the log carries refuses the folder" got `{:ok, …}`: I compared the running counter against the highest id rather than the `{"next":N}` marker's own value, and a later job had already raised the counter past it                                                                     | yes                                   |
| 4   | test code                                           | `JobTest` would not compile: "cannot invoke remote function String.Chars.to_string/1 inside a match" — an interpolated `#{state}` in an `assert {:error, "…"} =` pattern                                                                                                                                                 | yes                                   |
| 5   | test expectation                                    | `CLITest` verify: I had guessed the round 7 fixture's counts (`queued 2 … dead 0`); it is `queued 1 … dead 1`                                                                                                                                                                                                            | yes                                   |
| 6   | test expectation                                    | `check.sh`: `verify` on `$work/served` read 7 jobs, not 2 — the script had been played against that folder again after the compaction. Moved the `verify` up to just after the compaction                                                                                                                                | **no**, see loop 7                    |
| 7   | test expectation                                    | the moved assertion was still wrong (`leased 1, done 0` for what is `leased 0, done 1`)                                                                                                                                                                                                                                  | yes                                   |
| 8   | check harness                                       | `check.sh` "expected 'record j_2: …' in: " — `expect_body` greps the captured stdout, and a refusal is written to stderr. Added an `expect_error` helper                                                                                                                                                                 | yes                                   |
| 9   | style gate                                          | `mix credo --strict`: "Function body is nested too deep (max depth is 2, was 3)" at `Jobq.Store.write`. Extracted `append/2`                                                                                                                                                                                             | yes                                   |
| 10  | test code                                           | `mix format`: "unexpected reserved word: end" in `durability_test.exs` — my patch left a stray `end` where the `describe` block already closed                                                                                                                                                                           | yes                                   |

No loop came from the three behaviours the spec asks for themselves: the
well-formedness rule, the `503`-and-recover path, and `/queues` were all green
on their first run. The one real defect (loop 3) was in the counter rule the
spec calls "refused as before".

## Every check, green

    mix format --check-formatted
    mix compile --force --warnings-as-errors
    mix credo --strict            379 mods/funs, no issues
    mix dialyzer                  Total errors: 0
    mix test                      4 properties, 126 tests, 0 failures (three seeds)
    sh check.sh                   check.sh: ok
    mix run bench/bench.exs throughput expiry backoff

The bench, after the store began opening the log per batch: create 13,363/s on 8
connections, lease+ack 1,758/s on one worker and 9,365/s on 32, lease expiry to
hand-out 5 ms, backoff run_at to hand-out 1 ms. Nothing regressed against the
numbers in `REPORT-change.md` (397/s and 4,664/s for lease+ack), so the extra
`open`/`close` per batch disappears beside the `fsync` it sits next to, as
expected.

## Files changed

    lib/jobq/job.ex          + check_record/1 and record_key/1: the whole
                               well-formedness rule as one function over a raw
                               record, and the key a refusal names
    lib/jobq/store.ex          the replay validates every record and refuses by
                               key and rule; a `{"next":N}` counter must stand
                               above every id the log carries; each batch goes
                               through a log opened and closed for it; a write
                               that fails no longer stops the store — it moves
                               to a new epoch, tells the queue, and refuses the
                               commits still in flight from the old one
    lib/jobq/queue.ex          every operation inside a `try` (a raise, an exit
                               or a throw is that request's 503 and no more);
                               `{:store_epoch, n}` reloads the jobs from the
                               log; per-queue counts behind `GET /queues`; the
                               call deadline is the spec's 5 seconds
    lib/jobq/router.ex         `GET /queues`; everything unexpected inside a
                               request is 503 with the connection untouched
    lib/jobq/cli.ex            `jobq verify <dir>`; serve, compact, verify and
                               check all read the folder before anything else
    check.sh                   verify on the run's own folders, an ill-formed
                               folder refused by serve/compact/verify alike, a
                               torn last line still cut off, /queues over the
                               socket, the new exit codes; an `expect_error`
                               that reads stderr
    script/check.script        /queues while a queue has a job and after the
                               delete that empties it, and `PUT /queues`
    script/expected.txt        regenerated
    README.md                  change 2's shape, the epoch, verify, /queues
    test/jobq/job_test.exs     check_record: a test per state, the field rules,
                               the old shape, the key, and every record the
                               store writes
    test/jobq/store_test.exs   the refusals by key and rule, the counter rules,
                               and the write that fails keeping the store and
                               moving the epoch
    test/jobq/api_test.exs     /queues empty, by name with counts, a queue that
                               leaves the list, /health as the sum of the rows,
                               and a store fault answered 503 with the next
                               request answered normally
    test/jobq/cli_test.exs     verify on the fixture folders and on a
                               hand-written ill-formed one, the torn line, the
                               exit codes
    test/jobq/durability_test.exs
                               the read-only folder (write 503, read 200,
                               writable again, write 2xx, no restart) and the
                               same thing under eight concurrent producers

## Decisions the spec did not cover

1. **A record's "key" is its `id`.** This implementation's store is one
   append-only log, not a file per job, so a record has no key beside the `id`
   it carries. `check_record/1` therefore reads the key off the record, the rule
   "the record's key naming the job's id" becomes "the `id` field is `j_` and a
   counter", and a record with no readable id is named `?` in the refusal.

2. **The store opens the log for each batch instead of holding it open.** A file
   descriptor opened before a folder was made read-only goes on writing happily;
   with an open descriptor the service would never see an unwritable folder at
   all, and the spec's own required test (make the folder read-only, write,
   expect `503`) could not pass. Opening per batch costs one `open` and one
   `close` beside an `fsync`, which the bench shows is free, and it is also what
   makes the writes resume by themselves: the next batch simply opens again.

3. **A `503` is undone by reloading from the log, not by an undo record.** The
   queue moves a job in memory and hands the store the records, so on a failed
   batch the memory is ahead of the disk. Rather than unwind it, the queue
   throws its jobs away and replays the log — the state the disk agrees with.
   This is why an epoch is needed: commits the queue sent between the failure
   and the reload would otherwise land on the disk after the `503` that disowned
   them, so the store refuses anything tagged with the epoch it left. The store
   sends the epoch to the queue _before_ it answers the waiters, so a client
   that is told `503` cannot get its next request in ahead of the reload.

4. **`{"next":N}` must stand above every id the log carries.** The spec says a
   counter "lower than a job's number" is "refused as before", but the previous
   version quietly took the higher of the two. I read the sentence as the rule
   and implemented the refusal: a marker no higher than the highest id in the
   log (deleted ones included, since the counter must never hand one out twice)
   refuses the folder as a corrupt log, at the marker's line. A marker that is
   not a positive integer is refused as before.

5. **A line that is not a JSON object is still "corrupt", a JSON object that is
   not a job is "ill-formed".** The two refusals now say different things, and
   `{"id":"j_2","half":true}` moved from the first to the second. Both exit 1.

6. **`reason` belongs to no state.** The state table does not mention it, and a
   job failed back into `queued` keeps the reason it was failed with, so
   `check_record/1` allows a `reason` in any state and holds it to the field
   rule of `01-job-queue.md` wherever it appears.

7. **`verify` reports the states as they are on the disk.** It does not take a
   look first, so a lease that has run out is still counted `leased`. `verify`
   is a reading of the folder, not of the service the folder would become.

8. **`verify` creates the folder if it is not there**, the same way `serve` and
   `compact` already did, and then reports `0 jobs … next id j_1`. Only a path
   that cannot be made a folder is exit 1.

9. **The queue's call deadline is now 5 seconds, down from 15.** The spec makes
   "the queue did not answer within 5 seconds" a `503`, and the deadline that
   produces that answer is the one the router waits on.

10. **An unexpected failure is caught twice, in the queue and in the router.**
    The queue catches so that one request's raise does not take the process and
    every job in it down; the router catches so that a failure on the way to or
    from the queue is a `503` on that connection rather than a dropped
    connection. Both log the failure at `error` before answering.

11. **`jobq check` also refuses an ill-formed folder.** The spec names `serve`,
    `compact` and `verify`; `check` serves the folder, so refusing it there too
    is the same rule rather than a new one.
