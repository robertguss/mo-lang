---
title: "Step 11: Net, a TCP capability, brief for the worker"
created: 2026-09-13
updated: 2026-09-13
type: plan
tags: [runtime, effects, processes]
sources: [spec/programs/03-kv-store.md, spec/design-v0/03-semantics.md]
status: done
---

# Step 11: `Net`, a TCP capability

Program 3 needs a socket. This step adds the `Net` capability to the platform, the prelude, `Mo.Server`, and `Mo.Sim`, and makes processes run under `mo run`, which they cannot today.

## Orientation

`toolchain/src/server.zig`, `sim.zig`, `vm.zig`, `prelude.zig`, `PRELUDE.md`; `spec/design-v0/03-semantics.md` (effects, processes: direct-style I/O suspends and resumes; green threads; no `async`), `09-stdlib.md` rules; `spec/programs/03-kv-store.md` for what the API must make easy.

## Write scope

`toolchain/` and `examples/`, plus rows appended to `mo-wiki/spec/design-v0/09-stdlib.md` under a `## Net` heading. Branch `session-05`, one commit per part, push after every commit.

## Part A: processes under `mo run`

`Name.start` works in `main`: `Mo.Server` gets the same scheduler as `Mo.Sim` (one thread, run to quiescence), driven by `main`'s statements and by I/O events. `main` may `send` and `ask`; a process's `update` may call capabilities it was started with. A supervisor declared in the module supervises what `main` starts through it: `Payments.start(db, clock, events)` starts the supervisor with its children (decide the shape; zero new syntax: a supervisor is started like a process and returns nothing a program can misuse).

## Part B: `Net`

`platform.net: Net`. `net.listen(port, within:) : Result(Listener, NetError)`; `listener.accept(within:) : Result(Conn, NetError)`; `conn.read_line(within:) : Result(Option(String), NetError)` (`None` at end of stream, lines capped at 64 KiB, longer is `NetError.LineTooLong`); `conn.write(s, within:)`; `conn.close`; `net.connect(host, port, within:) : Result(Conn, NetError)`. `NetError`: `Timeout`, `Refused`, `Closed`, `LineTooLong`, `Busy`. Every call can wait, so every call takes `within:`. A `Conn` is a capability: it can be sent to a process (the accepting loop hands each connection to a worker process) and is closed when the process holding it stops.

## Part C: direct style over blocking calls

Chapter 3: `conn.read_line(within: 30.s)` reads like Go and blocks like Erlang. Implement with `std.Io` so that a process blocked in `read_line` does not block the scheduler: other processes keep receiving messages. Pick the simplest thing that is correct under `std.Io`'s threaded implementation (a thread per blocked call is acceptable in this step; record it). Deadlines are real: a call past `within:` returns `Timeout` and the socket state is defined.

## Part D: `Mo.Sim`

`Net.fixture()` with in-memory listeners and connections, so a test can start the server process, connect a fixture client, and drive the protocol with no real socket; fault injection from step 9 applies (`Timeout`, `Closed` by seed).

## Part E: corpus and numbers

`examples/effects/net.mo`: an echo server process and a client test under `Mo.Sim`; `examples/programs/echo/` runs a real socket echo through `mo run` with a test client (two `# run:` lines: server in the background is not possible from the corpus test, so the program spawns its own client process in `main`, talks to itself over localhost, and prints the round trip). Bench row `echo-1k`: 1,000 round trips over localhost.

## Also

The `usage:` text in `main.zig` must list `fmt` and `fix`.

## Done when

Corpus green, echo over a real socket, `Net` rows in `09-stdlib.md`, bench rows, pushed, decisions listed.

## Related
- [[interpreter-step-9]]
- [[d16-direct-style-io]]
- [[d12-concurrency-at-the-edges]]
