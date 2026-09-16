# Round 10, the Elixir control run: `jobq`

An agent that had not seen the program before built `jobq` from
`spec/01-job-queue.md` in Elixir 1.18 on OTP 27, in
`experiments/control-run/elixir/jobq`. What follows is the report the brief
asked for: the wall-clock, the loops to green by cause, the dependencies, the
wall-clock of the finished program's own check-and-test command, and the
decisions the spec did not make.

## What was built, and what was left out

Everything `01-job-queue.md` says about the API, the jobs, the durability, the
usage and the tests is in. The Mo-specific lines are not, as the brief said to
leave them: the `Recipes.Store` recipe and `mo check --recipe`, the `requires` /
`ensures` / `invariant` contracts, the `within:` literals and their count, the
`never` clauses as a language construct, `mo run --sim`, and the runtime-surface
questions of the last section. Where a Mo construct had an obvious equivalent in
an ordinary program, the equivalent is there and is tested:

- the `never`s are a checker, `Jobq.Test.Never`, that reads the store's log
  after a run and refuses a job leased while already leased, a `attempts` over
  `max_attempts`, a lease that did not raise `attempts` by one, and a done or
  dead job that moved again;
- the `requires` are `Jobq.Job`'s validators, each with its own rejection test;
- `--sim` is an injectable `:fault` function on the store, used by a 100-round
  run with two injected write failures in it.

`spec/01b-job-queue-change.md` (scheduled jobs, backoff, the `tries` rename) is
the *next* round's brief and was deliberately not implemented: this program is
the round 7 shape the change is written against.

## Wall-clock

| | |
|---|---|
| Start | 2026-09-15 23:56 UTC |
| Green, all four checks and `check.sh` | 2026-09-16 00:27 UTC |
| Report written, work committed | 2026-09-16 00:40 UTC |
| **Build to green** | **31 minutes** |
| **Everything, the bench and this report included** | **44 minutes** |

One session, one agent, no restarts and no rewrites: every line of the program
that was written is in the program.

## Loops to green, by cause

Fourteen failures in all, each with what it said and whether the next edit
fixed it. Every one of them was fixed by the next edit; none needed a second
attempt.

| # | Cause | Diagnostic | Fixed by the next edit |
|---|---|---|---|
| 1 | my slip | `variable "from" is unused` (`--warnings-as-errors`) | yes |
| 2 | **program bug** | `nil` came out of the encoder as the string `"nil"`: Erlang's `:json` turns an unknown atom into a string | yes |
| 3 | my test | a hand-computed ISO timestamp in a fixture was six days off | yes |
| 4 | my slip | `syntax error before: catch` — a `catch` inside an anonymous `fn` | yes |
| 5 | **program bug** | `Protocol.UndefinedError ... String.Chars ... {127,0,0,1}`: the client built its `Host` header with `to_string/1` on an IP tuple | yes |
| 6 | **program bug** | `j_3` handed out twice: the id counter went back when the highest job was deleted and the log replayed | yes |
| 7 | **program bug** | after fixing 6, `Store.read/1` on a directory with no log still returned the old shape and `compact` fell through it | yes |
| 8 | my test | the fault run left 36 jobs leased and 3 jobs alive: the test never retried a 503 and raced the restart window | yes |
| 9 | my slip | `imported ExUnit.CaptureIO.with_io/1 conflicts with local function` | yes |
| 10 | **program bug** | a listener that cannot bind killed the command with an `EXIT` instead of printing and exiting 1 | yes |
| 11 | lint | `mix credo --strict`: 11 findings (4 un-aliased nested modules, 4 one-clause `with`s, one function nested too deep, one too complex, one `Enum.count/2 > 0`) | yes |
| 12 | types | `mix dialyzer`: 3 errors (an unreachable `reason_phrase/1` clause; `health/1` calling `run(ref, :health)` against a `tuple()` spec) | yes |
| 13 | style | `mix format --check-formatted` on two files | yes |
| 14 | my bench | the expiry lag came out at **-196 ms**, which would have meant a job leased before its lease ran out: two `mix run` invocations had landed on one temporary directory, because a node's unique integers start over in every VM | yes |

By cause: **5 program bugs**, **3 of my own slips** (two of them caught by the
compiler before a test ran), **3 bugs in the tests and the bench**, **3 tool
findings** (credo, dialyzer, formatter). Five of the fourteen were caught by a
compiler or a tool rather than by a test, and four of the five program bugs
were caught by a test that was written before the code it broke.

Worth naming twice. Loop 6 is the only bug that a reader of the spec would call a
real defect — "a counter that never repeats, per service" is a line of the
spec, and deleting the highest job then restarting handed its id out again. The
test that caught it existed because the spec's sentence was turned into a test.
And loop 14 is the one measurement that would have read as a broken `never` if
it had been believed: the number was impossible, the cause was in the bench, and
the program was right. A measurement that cannot happen is worth more attention
than a measurement that looks bad.

## Dependencies

**Run time: none.** The service uses OTP's `:gen_tcp`, `:inet`'s HTTP packet
mode, OTP 27's `:json` and Elixir 1.18's `JSON`, `:gb_sets`, `Registry`,
`Supervisor`, `Task.Supervisor` and `GenServer` — the standard library, nothing
else. The escript is self-contained.

**Dev and test: 3 direct, 4 transitive.**

| Package | Version | Why | Where |
|---|---|---|---|
| `credo` | 1.7.19 | `mix credo --strict` | dev, test |
| `dialyxir` | 1.4.8 | `mix dialyzer` | dev |
| `stream_data` | 1.4.0 | the property tests | dev, test |
| `bunt` | 1.0.0 | credo's colours | transitive |
| `file_system` | 1.1.1 | credo's watcher | transitive |
| `jason` | 1.4.5 | credo's config | transitive |
| `erlex` | 0.2.9 | dialyxir's parser | transitive |

Not one of them ships in the binary.

## The finished program's own check-and-test

    mix compile --warnings-as-errors && mix dialyzer && mix credo --strict && mix test && ./check.sh

**12.4 s** wall-clock, everything green, with a warm dialyzer PLT (14.3 s the
first time it was timed, and the run-to-run spread is about that). Built from
nothing the PLT costs another **78 s**, once per Erlang/Elixir version.

| Command | Wall-clock |
|---|---|
| `mix compile --warnings-as-errors` | 0.5 s |
| `mix dialyzer` | 2.8 s |
| `mix credo --strict` | 0.9 s |
| `mix test` (3 properties, 77 tests) | 2.4 s |
| `./check.sh` (escript build, two services, real sockets, 30 requests and a diff, then the client, compact and the exit codes) | 1.6 s |

## Measured

All of it on the machine this round runs on: the exe.dev VM, 4 vCPU, 16 GiB,
Linux 6.12.93, ext4, Elixir 1.18.5 on OTP 27 (erts 15.2.7). `mix run
bench/bench.exs` prints every line of this table; the bench is a client, not a
harness, and talks to a real service over a real local socket with one
keep-alive connection per worker.

| What the spec asks for | Measured |
|---|---|
| leases and acks per second, 1 worker | **401/s** (20,000 lease+ack pairs in 49.9 s) |
| leases and acks per second, 32 workers | **4,974/s** (20,000 pairs in 4.0 s) |
| creates per second, 8 connections | **3,403/s** |
| lag from a lease running out to the job being handed out again, under a steady stream of lease requests | **1–2 ms** |
| resident memory at 100k jobs | **84 MiB** in the BEAM, of which **33 MiB** is the queue process; 164–199 MiB RSS across runs for the whole node, the bench's own 100k job bodies included |
| replay of a 1M-record log | **7.5 s** to read and parse 191 MiB; **10.1 s** for a service to be up on it |
| restart with 10,000 leased jobs | **108 ms** |
| 1,200 connections that say nothing | **9.9 MiB** on the node, and a producer's create in the middle of them takes **1.5 ms** (median of 20; best 1.2 ms) |

The two throughput numbers are the whole design in one line. One worker pays
the disk for every record: a lease and an ack are two `fsync`s, and an `fsync`
of a small append on this filesystem costs about 2 ms, which is the 401/s.
Thirty-two workers do not pay thirty-two times, because the records that arrive
while an `fsync` is in flight are written and synced together — the service does
12× the work for 1× the disk. Nothing about that costs a reply its durability:
each caller is answered after the `fsync` that carried *its* record.

Replay is the number a reader should not like. 7.5 s for a million records is
a parse of 191 MiB, one JSON object at a time, and a service with a log that
size is 10 s from being up. That is what `jobq compact` is for, and the spec
asks for it; but nothing runs it on its own, and this program does not tell an
operator the log has grown. The report's own decision 18 says compaction takes
no lock either. A next round would earn its time here before anywhere else.

Where the escript differs from `mix run`: the measurements above are under
`mix run`, in the same VM as the bench. The escript serves the same code with
the same BEAM; `check.sh` runs it, and its 30 requests over a socket, plus a
build, take 1.6 s.

## Decisions the spec did not cover

1. **No framework.** A `:gen_tcp` acceptor pool and OTP's `:http_bin` packet
   parser rather than Plug/Bandit. Three reasons: the control run counts
   dependencies and this way the service has none; the spec's listener section
   is about what a connection that says nothing costs, which on the BEAM is a
   sleeping process rather than a slot in an acceptor's mailbox, and that is
   easier to show with the acceptors in view; and OTP's packet mode is a real
   HTTP parser from the standard library, so hand-rolling one was never on the
   table.
2. **JSON.** OTP 27's `:json` through a thin `Jobq.Json`, with `{:obj, [{k, v}]}`
   for an object whose keys keep their written order. A map's key order is not
   something to bet a byte-for-byte transcript on.
3. **The log.** `<dir>/jobq.log`, one JSON object a line, the last record of an
   id wins, and a delete writes `{"id":"j_3","deleted":true}`.
4. **The torn-line rule.** A final line with no `\n` is dropped on replay (a
   crash mid-write); a *complete* line that is not a record is a corrupt log and
   the service refuses to start, exit 1. Silently skipping it would lose a job.
5. **The id counter across a compaction.** Compaction drops the deleted jobs and
   with them the log's memory that their ids were handed out, so it writes
   `{"next":N}` as the first line when the counter stands above the highest job
   it kept. This is the one line of the log that is not a job.
6. **One `fsync` for many records.** The queue hands the store the records of an
   operation and the reply it owes; records that arrive while an `fsync` is in
   flight are written and synced together and each caller is answered after its
   own record is durable. This is why 32 workers go eleven times faster than one
   and not thirty-two times: the disk is paid for once per batch.
7. **A write that fails.** The store tells that batch's waiters the store is
   down and stops; `:rest_for_one` takes the queue with it and the queue comes
   back by replaying the log, which is the state the disk agrees with.
8. **503.** Not a status the spec lists. It is what a caller gets when the store
   is not accepting writes or the queue is restarting — the alternative was to
   hold the request, which turns one bad disk into a hung service.
9. **Unknown fields are 400**, in a body and in the query string alike. The spec
   says a missing field or one of the wrong shape is 400; an unknown one is the
   same kind of mistake, and `01b` confirms it later ("like any unknown or
   missing field").
10. **`reason` is optional** on `POST /jobs/{id}/fail`, and a fail without one
    keeps the reason the job already had. A reason is a string of at most 4 KiB
    under the payload's character rule.
11. **The token is checked before the route.** An unknown route with no token is
    401, not 404: a service should not tell an anonymous caller which routes it
    has. `/health` takes no token, as the spec says.
12. **Any non-empty bearer string is a token** and names the worker. The spec
    says "any client may produce or work"; there is no registry of workers, so
    there is nothing to check a name against.
13. **Control characters in a payload** are everything below `0x20` except `\n`,
    plus `0x7F`.
14. **Request bodies over 128 KiB are 400** before they are read (the payload
    limit is 60 KiB), a body needs a `content-length`, and
    `transfer-encoding: chunked` is 400. The service is talked to by its own
    client and by scripts; chunked upload buys nothing and costs a parser.
15. **Keep-alive is served**; a connection is dropped after 10 s with no
    request and a half-sent request is dropped after 10 s. A connection is a
    process, so the number of silent ones is bounded by memory rather than by
    room in an acceptor's mailbox: 1,200 of them are a test, they cost about
    10 MiB on the node (the bench holds the other end of all 1,200, so the
    service's share is roughly half of that), and a producer's create in the
    middle of them takes 1.5 ms.
16. **The idle look ticks every 100 ms**, which is the upper bound on "one look"
    for a lease that runs out with nobody asking. Under any traffic at all the
    look happens on the request instead.
17. **`serve` creates the directory** if it is not there, and exits 1 if it
    cannot.
18. **`compact` assumes the service is stopped.** It writes a temporary file,
    `fsync`s it, renames it over the log and `fsync`s the directory; it does not
    take a lock, and running it against a live service is not defended against.
19. **The clock is a function** the service is started with, so the lease tests
    move time by hand instead of sleeping. In `serve` it is the system clock, as
    the spec's "the clock it reads is `main`'s" asks.
20. **The client prints `<status>` or `<status> <body>`**, one line, and `check`
    prints `> ` for what it played and `< ` for what came back. A script line is
    `<token> <method> <path> [<json>]`, `#` starts a comment, a line that is not
    one of those is an error and exit 1.
21. **Timestamps are ISO-8601 UTC with milliseconds** (`2026-09-16T00:27:40.000Z`).
    `check.sh` normalizes them and the uptime out of the transcript, since they
    are the only two things one run does not share with the next.
22. **An ack after a re-lease by the same worker name** acks the new lease.
    There is no lease token in the API, so the service cannot tell the two
    leases of one name apart; the spec's 409 is for a lease held by someone
    else, and that is what it does.
23. **A listing sorts every job by id and takes 100.** At 100k jobs a listing
    costs a scan; the hot path — create, lease, ack, fail — does not, and the
    spec's cap of 100 is on what comes back rather than on what is looked at.
24. **The binary is an escript** (`mix escript.build`), and the application
    callback starts one thing, a `Registry`, so a node can run several services
    and the tests can run one per test case.

## What the reader may want to look at

- `lib/jobq/queue.ex` — the whole state machine, and the *look* that makes a
  lease a deadline rather than a timer.
- `lib/jobq/store.ex` — the log, the batch `fsync`, and what a failed write does.
- `test/support/never.ex` — the spec's `never`s as a checker over the log.
- `script/check.script` and `script/expected.txt` — the program-level check.
