---
title: "Step 20: the runtime owns the loop, brief for the worker"
created: 2026-09-13
updated: 2026-09-13
type: plan
tags: [runtime, processes, stdlib, laws]
sources: [decisions/decision-log.md, deep-dives/outside-review-2026-09-13-response.md, plans/program-4.md, spec/design-v0/03-semantics.md]
status: proposed
---

# Step 20: the runtime owns the loop

Three servers in a row (kv, httpd, notes) wrote `for _ in 0..10_000` twice around `accept` to satisfy the no-`while` law with a bound nobody chose. Robert's call (13 Sep, evening): no `loop` keyword; the runtime makes the calls that wait and delivers each result to a process as a message, as Erlang's active-mode sockets do. A process never loops; the scheduler is the loop.

## Orientation

`spec/design-v0/03-semantics.md` (processes, the failure model), `09-stdlib.md` (`## Net`, `## Http`), `toolchain/src/sim.zig`, `turns.zig`, `server.zig`, `net.zig`, `http.zig`, `runtime/mo_rt.c`, `caps.zig` (step 18's rules for handles and fields), the four servers (`examples/programs/echo`, `kv`, `httpd`, `notes`) and `examples/effects/net.mo`, `http.mo`, the decision rows of 13 Sep evening.

## Write scope

`toolchain/`, `examples/`, and these spec lines only: the `## Net` and `## Http` tables and their capability paragraphs in `09-stdlib.md` and `PRELUDE.md`, the process paragraph of `03-semantics.md` on what a message may carry; each with a "Session 5, step 20" line. Branch `session-05`, one commit per part, push after every commit.

## Part A: a message may carry a capability

A `message` line may declare a field of a capability or handle type; a sender may put in it only a value it holds (it always does, by construction); struct, state, and enum fields stay refused as step 18 left them. `flows` follows the field. Both runtimes deep-copy messages today; a capability in a message moves, it is not copied, and the sender's copy is closed to further use if the checker can see it (record what it does when it cannot). A corpus file proves a `Conn` handed from one process to another by a message.

## Part B: the rows

`Net.serve(listener, into: Handle(P), idle: Duration)`: the runtime accepts on the listener from that call on and sends `P` an `Accepted(conn: Conn)` per connection; `P` must declare that message (a check-time diagnostic if not). `Conn.lines(into: Handle(P), idle: Duration)`: every line arrives as `Line(text: String)`, the end of the stream as `Closed`, a line too long as `LineTooLong`, and no line within `idle` as `Idle`, after which the connection is closed. `Http.serve(listener, into: Handle(P), idle: Duration)`: each request as `Accepted(exchange: Exchange)`. The runtime stops accepting or reading while the target mailbox is within a few messages of its bound and resumes when it drains; record the numbers. `Mo.Sim` delivers these messages by seed as it delivers any other, and `--faults` injects `Closed` and `Idle`. Both runtimes; `Net.fixture()` and `Http.fixture()` included.

## Part C: the servers

Rewrite `echo`, `kv`, `httpd`, `notes`, `effects/net.mo`, and `effects/http.mo` on the rows: no `for` around `accept` or `read_line` anywhere in `examples/`. Every program must print exactly what it printed before on its `# run:` lines, or the `.expected` file changes with a sentence in the commit saying why. `--sim 100` must hold for all of them.

## Part D: numbers

For each server: lines before and after, fictional bounds before and after (must be zero after), and `kv-10k-get`, `kv-10k-get-c`, `http-1k`, `http-1k-c` before and after; a 32-client run of kv and notes; the connection count at which a process per connection fails today, recorded as the memory step's target.

## Done when

Green, no `for` around a waiting call in `examples/`, the rows in both runtimes and both spec tables, the fixture and faults, the numbers, pushed, decisions listed.

## Related
- [[interpreter-step-19]]
- [[outside-review-2026-09-13-response]]
- [[program-4]]
- [[d31-effects-never-hide-in-a-value]]
