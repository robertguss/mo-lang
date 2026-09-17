# Program 1: `jobq`, a durable job queue with an HTTP API

The spec altitude of program 1 from the program menu, the founding premise's first real test: an agent builds a service that must not lose work, and Robert reads only this page, the exposed signatures, the contracts, the `never`s, and the `verified:` lines. Written by Claude (Fable) in session 5, night of 13–14 Sep 2026, after step 21. A worker implements it in Mo. **Status:** implemented in session 5; the program of rounds 7 and 8 (`plans/control-run-7.md`, `plans/control-run-8.md`) and, as `jobq`, of measurement 1 (`plans/bodies-as-cache.md`); its changes are `01b` to `01f`.

## Intent

`jobq` keeps jobs for producers and hands them to workers one at a time: a producer creates a job in a named queue, a worker leases the next job for a while, then acks it or fails it; a lease that runs out puts the job back; a job that fails too often is dead. Every change is durable before it is answered. It stresses processes, supervision, deadlines, the store recipe, and `never` clauses that a test can trip.

## The package story

The store is `Recipes.Store` (`examples/recipes/store.mo`), implemented in the program's own modules as `notes` did, and checked against the recipe with `mo check --recipe`. If `notes`'s implementation fits, it is copied by hand and the report says so. No other recipe; the queue is the program.

## Jobs

A job has an `id` (`j_` and a counter that never repeats, per service), a `queue` name (1 to 64 bytes of letters, digits, `-`, `_`), a `payload` (0 to 60 KiB, UTF-8, no control characters but `\n`), `max_attempts` (1 to 100), `attempts` (leases so far), a `state`, and for a leased job the `worker` that holds it and `lease_until`. States:

```
queued  --lease-->  leased  --ack-->   done
                    leased  --fail-->  queued        (attempts < max_attempts)
                    leased  --fail-->  dead          (attempts == max_attempts)
                    leased  --lease runs out-->  queued or dead, by the same rule
```

A lease is a deadline, not a timer: the queue treats a lease as run out the next time it looks at the job (a lease request, an ack, a fail, a read, or the listener's `Idle`), and the clock it reads is `main`'s. A worker whose lease ran out and who acks anyway is told `409`; the job may already belong to someone else.

## The API

Every request carries `authorization: Bearer <token>`, as in `notes`; a missing or empty token is `401`. Any client may produce or work; the token names the worker on a lease.

```
POST   /jobs                  {"queue": "emails", "payload": "...", "max_attempts": 3}
                              → 201 {job}
GET    /jobs/{id}             → 200 {job}  |  404
GET    /jobs?queue=q&state=s  → 200 {"jobs": [ {job}, ... ]}  by id, at most 100; either filter optional
DELETE /jobs/{id}             → 204 when queued, done, or dead  |  409 when leased  |  404
POST   /queues/{queue}/lease  {"lease_ms": 30000}   → 200 {job}  |  204 when nothing is queued
POST   /jobs/{id}/ack         → 200 {job}  |  409 when the caller does not hold a live lease on it  |  404
POST   /jobs/{id}/fail        {"reason": "..."}     → 200 {job}  |  409  |  404
GET    /health                → 200 {"queued": n, "leased": n, "done": n, "dead": n, "uptime_ms": n}   no token
```

`{job}` is `{"id", "queue", "state", "payload", "attempts", "max_attempts", "created_at", "updated_at"}` plus `"worker"` and `"lease_until"` while leased, plus `"reason"` after a fail. `lease_ms` is 100 to 3,600,000 and defaults to 30,000. A body that is not JSON, a missing field, or a field of the wrong shape is `400 {"error": "..."}`; a method the route lacks is `405`; an unknown route `404`. Timestamps are ISO-8601 UTC from the clock. A lease hands out the oldest queued job of that queue first.

## Durability

Every create, lease, ack, fail, delete, and lease expiry is in the store before its response is sent, one record per job under its id. On start the store is replayed; a job that was leased when the service stopped is queued or dead by the lease rule at its next look. `jobq compact <dir>` rewrites the log to one line per live job and exits.

## Usage

```
jobq serve <dir> [--port N]      default port 7900
jobq compact <dir>
jobq client <host> <port> <token> <method> <path> [<json>]      one request; prints status and body
jobq check <dir> <script>         serve on a free port and play `<token> <method> <path> [<json>]` lines through the client
```

Exit 2 on a usage error, 1 if `<dir>` cannot be opened or the port cannot be bound.

## Nevers

- A job is never held by two workers at once.
- A done job is never leased again, and a dead job is never leased.
- A job's attempts never exceed its `max_attempts`.
- A response is never sent before its record is durable.
- A job is never lost: after replay, every job created and not deleted is present with its last state.
- A lease that ran out never blocks the job for longer than one look.

## Contracts the reader expects to see

`requires` on the queue name, the payload, `max_attempts`, and `lease_ms`, each with its `rejects`; `ensures` on `lease` that the job it returns is leased to the caller with `attempts` one higher; `ensures` on `ack` that the job is done; `invariant`s on the queue process that a test can trip through a message the process accepts, and only those: an `invariant` no message can break is documentation and is left out, and the report names each one left out and why.

## Deadlines

Every call that can wait carries `within:`. The report counts the `within:` literals the program writes and, for each, whether its number was chosen for that call or derived from an enclosing deadline (a request's, a lease's); this is the count the decision log asked for after the research agenda.

## The listener

`HttpListener.serve(into:, idle:)` counts accepted connections that have sent no request against the acceptor's mailbox bound, about 1,000 with the default bound (step 21's finding), and `idle:` is what frees them; the spec asks for `idle:` chosen with that in view and stated in the report, and for a test in which 1,200 connections that send nothing do not stop a producer's request from being answered.

## Tests the reader expects to see

Unit tests for the JSON shapes, the routes, and each status; the store recipe's tests passing on the implementation through `mo check --recipe`; a property that create then get round-trips any valid payload; a lease test in which two workers race for one job and exactly one holds it; a lease that runs out and is leased again with `attempts` at 2, and one that runs out on its last attempt and is dead; a replay test that creates, leases, stops, starts again, and finds the lease run out; a `--sim 100` run with injected `Fs` and `Http` failures under `--until` in which every response was correct or a `503` with the store unchanged, no job was ever held twice, and every job is done or dead once the faults stop and the workers keep working; and a program-level check in `examples/programs/` through a real socket from `jobq client`.

## Measured

Leases and acks per second with 1 and with 32 workers over a local socket, under `mo run` and as a binary; the lag between a lease running out and the job being handed out again under a steady stream of lease requests; resident memory at 100k jobs; replay time for a 1M-record log; restart with 10,000 leased jobs; the `within:` count; loops to green by cause; wall-clock; and any program a law blocked (the Q16 ledger).

## The runtime surface, later

Program 1 is the testbed for directions 37 to 40. The report lists the questions the worker wanted to ask the running service during the measurements that the runtime could have answered (which process holds job `j_9`, what a stuck lease's state is, the last ten messages a queue process took); step 23 built the surface from that list (chapter 3, chapter 9) against that list, as a capability held by `mo run` and off in a binary unless `main` holds it.
