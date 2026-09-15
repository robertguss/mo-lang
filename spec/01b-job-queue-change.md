# Program 1, change 1: scheduled jobs, retry backoff, and the `tries` rename

A change to `jobq` as specified in `01-job-queue.md`, the first change any program in this project has received after it was finished. Written by Claude (Fable) in session 7, 15 Sep 2026, for control run 8, the maintenance round: a fresh agent that has never seen the program gets the finished program, this page, and the instruction that the tests must pass and the service must keep its durability. Everything `01-job-queue.md` says still holds unless a line below changes it. The shape is a product ticket: a producer wants to delay a job, a worker wants a failed job to wait before it is tried again, an operator wants a dead job back, and the API's counters get the names the team uses.

## What changes, in one screen

1. A job may be **scheduled**: created with a delay, or put back with a backoff after a fail, it waits until its `run_at` and is queued at the next look after that.
2. A dead job may be **retried** through a new route, which puts it back in its queue with its tries reset.
3. `attempts` and `max_attempts` are renamed **`tries`** and **`max_tries`** everywhere the service speaks: requests, responses, listings, and the records it writes.
4. **A log the old service wrote still opens.** The rename and the new fields change the record; the store must replay a log written before this change, read the old names, and after `compact` hold only the new ones.

## Jobs

A job now has `tries` (leases so far; was `attempts`), `max_tries` (1 to 100; was `max_attempts`), `backoff_ms` (0 to 3,600,000, default 0, fixed at creation), and while scheduled a `run_at` timestamp. States:

```
created with delay_ms = 0  -->  queued
created with delay_ms > 0  -->  scheduled            run_at = created_at + delay_ms

scheduled  --run_at reached, at the next look-->  queued

queued     --lease-->  leased
leased     --ack-->    done
leased     --fail, or lease runs out-->  dead                 (tries == max_tries)
leased     --fail, or lease runs out-->  queued               (tries < max_tries, backoff_ms == 0)
leased     --fail, or lease runs out-->  scheduled            (tries < max_tries, backoff_ms > 0)
                                                              run_at = now + backoff_ms
dead       --retry-->  queued                                 tries = 0
```

`run_at` is a deadline read the same way a lease is: a scheduled job whose `run_at` has passed is queued at the next look (a lease request on its queue, a read of it, a listing, `/health`, or the listener's `Idle`), the move is written to the store like a lease running out, and the clock it reads is `main`'s. `delay_ms` is 0 to 86,400,000 and is not stored; `run_at` is. A retry keeps the job's `queue`, `payload`, `max_tries`, and `backoff_ms`, sets `tries` to 0, drops `reason`, `worker`, and `lease_until`, and the retried job takes its place in the queue by `id` like any other queued job.

A lease still hands out the oldest queued job of that queue first, oldest by `id`; a job that was scheduled and is now due counts as queued at that look, in the same order.

## The API

Unchanged routes keep their statuses. What changes:

```
POST   /jobs                  {"queue", "payload", "max_tries", "delay_ms"?, "backoff_ms"?}
                              → 201 {job}         delay_ms and backoff_ms default to 0
GET    /jobs?queue=q&state=s  → state may now be scheduled
DELETE /jobs/{id}             → 204 when queued, scheduled, done, or dead  |  409 when leased  |  404
POST   /jobs/{id}/retry       → 200 {job}  |  409 when the job is not dead  |  404
GET    /health                → 200 {"queued", "scheduled", "leased", "done", "dead", "uptime_ms"}
```

`{job}` is `{"id", "queue", "state", "payload", "tries", "max_tries", "backoff_ms", "created_at", "updated_at"}` plus `"run_at"` while scheduled, plus `"worker"` and `"lease_until"` while leased, plus `"reason"` after a fail. A request that still says `attempts` or `max_attempts` is `400`, like any unknown or missing field; the old names are gone from the API. `delay_ms` or `backoff_ms` out of range, or not an integer, is `400`. `/retry` on a leased, queued, scheduled, or done job is `409`. `/retry` takes the caller's token like every route and needs no body.

## Durability

Every create, lease, ack, fail, delete, retry, lease expiry, and **scheduled-to-queued move** is in the store before its response is sent. The record a job is written under keeps its key; its fields are the new ones (`tries`, `max_tries`, `backoff_ms`, `run_at` while scheduled).

**Replay of an old log.** A folder this implementation's previous version served (the finished round 7 program, before this change) opens and replays without an error and without a tool: a record that says `attempts` and `max_attempts` is read as `tries` and `max_tries`, a record without `backoff_ms` reads as 0, and a record with neither `run_at` nor a state of `scheduled` is what it was. From the first write on, the service writes only the new names. `jobq compact <dir>` on such a folder leaves a log with no old name in it. A job that was leased when the old service stopped is queued, scheduled, or dead by the rules above at its next look. Nothing about the log's framing, its location, or its torn-line rule changes.

## Usage

Unchanged. `jobq check` plays the same script lines; a script may now say `POST /jobs/{id}/retry`, and its JSON uses the new field names. The program's own check script and its expected output are updated with the change.

## Nevers

The list from `01-job-queue.md` with the lines that change or are added:

- A job is never held by two workers at once. *(unchanged)*
- A done job is never leased again. A dead job is never leased **until it is retried**, and a retry never touches a job that is not dead.
- A job's `tries` never exceed its `max_tries`.
- A scheduled job is never leased before its `run_at`.
- A response is never sent before its record is durable, **the scheduled-to-queued move included**.
- A job is never lost: after replay, **of a log the old service wrote or the new one**, every job created and not deleted is present with its last state.
- A lease that ran out, or a `run_at` that passed, never blocks or holds back the job for longer than one look.

## Contracts the reader expects to see

`requires` on `delay_ms` and `backoff_ms` with their `rejects`; `ensures` on `retry` that the job it returns is queued with `tries` at 0; the `ensures` on `lease` now says `tries` one higher; any `invariant` on the queue process that named a state list or a counter is updated, and the report says which contracts and `never`s the change forced open and which it left alone. In Go and Python the equivalent is the checks the program already carries (its `contract` package or module, its `never` calls in the tests, its checkers in `check.sh`): they are kept, extended the same way, and green.

## Tests the reader expects to see

The existing tests still pass, updated only where a name or a state list changed. Added: a job created with `delay_ms` is not leased before `run_at` and is leased after it, with `tries` at 1; a fail with `backoff_ms` puts the job in `scheduled` with `run_at` at `now + backoff_ms`, and a lease on that queue before then returns `204`; a fail with backoff on the last try is dead; a run-out lease with backoff is scheduled, without backoff queued; a retry of a dead job is queued with `tries` at 0 and is leased again; a retry of a queued, leased, scheduled, or done job is `409`; `/health` counts scheduled jobs; a listing with `state=scheduled`; a replay test that starts the service on a folder the previous version wrote (the program's own `data/` folders and fixtures from before the change count, and so does a log written by hand in the old shape) and finds every job with its state, then compacts and finds no old name; the `--sim` or equivalent fault run still green with the new transitions in it; the program-level check script extended with a delayed job, a backoff, and a retry.

## Measured, for the round

The round's page (`plans/control-run-8.md`) says what is measured. For the maintainer nothing is asked beyond the report the previous version's brief asked for: loops to green by cause, wall-clock, and a numbered list of the decisions this page did not cover.
