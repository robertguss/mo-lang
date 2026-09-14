---
title: "Step 23: the runtime surface, brief for the worker"
created: 2026-09-14
updated: 2026-09-14
type: plan
tags: [runtime, agents, tooling, processes]
sources: [directions/d37-runtime-mcp-surface.md, directions/d40-structured-runtime-events.md, spec/design-v0/03-semantics.md, plans/program-1.md, decisions/decision-log.md]
status: in-progress
---

# Step 23: the runtime surface

Directions 37 and 40, built against the nine questions program 1's worker wanted to ask its running service ([[d37-runtime-mcp-surface|direction 37]], "Program 1's questions"). Robert's call (13 Sep night): the surface is a capability, on under `mo run` and `mo test`, off in a binary unless `main` holds it. Chapter 3's new section "The runtime surface" is the semantics; this step is the rows, the events, and the development on-ramp. No MCP server yet: an HTTP form of the same surface is the on-ramp, and an MCP wrapper is a later step. No syntax.

## Orientation

`spec/design-v0/03-semantics.md` (the runtime surface section, the failure model), `directions/d37-runtime-mcp-surface.md` (the nine questions), `d40-structured-runtime-events.md`, `toolchain/src/sim.zig`, `turns.zig`, `sources.zig`, `server.zig` (`Platform`), `contracts.zig` (the crash report's fields), `runtime/mo_rt.c`, `examples/programs/jobq/` (the program the questions came from), the decision rows of 13 Sep night (the surface is a capability) and 14 Sep night.

## Write scope

`toolchain/`, `examples/`, and these spec lines only: a `## Runtime` table in `09-stdlib.md` and its rows in `PRELUDE.md`, the `Platform` row for `runtime`, the `mo run` and `mo build` lines of `toolchain/README.md`; each with a "Session 5, step 23" line. Branch `session-05`, one commit per part, `Step 23 part X` in the subject, push after every commit, `zig build test` green at every commit.

## Part A: the events

A bounded ring per program (the bound a `mo run --events N` flag and an `MO_EVENTS=N` variable for a binary, default 4,096) of structured events: `Updated` (process, message name, duration, time spent waiting in calls, the call it waited longest in), `Started`, `Ended`, `Restarted` (with the count so far), `Crashed` (with the report's fields: seed, the clause, the message, the state before), `Overflowed` (sender, target), `TimedOut` (process, the call), `SourcePaused` and `SourceResumed` (source, target, in flight). Each event carries the runtime's monotonic time. Recording costs are measured (part D). Under `Mo.Sim` the ring is kept too, and a failed seeded test prints its last events after the interleaving. Both runtimes.

## Part B: the capability

`Platform` gains `runtime: Option(Runtime)`: `Some` under `mo run` and `mo test`, `None` in a binary unless built with `mo build --surface`. `Runtime` rows, each `within:` as every call that can wait:

- `processes()` → `List(ProcessInfo)`: id, name, alive, mailbox depth and bound, what call it is waiting in if any, restarts so far, its region's bytes.
- `state(id)` → `Result(String, RuntimeError)`: the process's state rendered as the crash report renders it, a snapshot between updates.
- `recent(id, n)` → `List(Event)`: the last `n` events of that process; `events(since: Time, n)` → the ring since a time.
- `crashes(n)` → `List(Event)`: the last `n` `Crashed` events.
- `sources()` → `List(SourceInfo)`: kind, target, connections in flight, paused.
- `memory()` → `MemoryInfo`: total resident, regions, packed values, per process the largest few.
- `slowest(n)` → `List(Event)`: the `n` longest `Updated` events in the ring.
- `send(id, text)` → `Result(none, RuntimeError)`: delivers a message the process declares, parsed from its printed form, and records it; `pause(id)`, `resume(id)`: hold a process's deliveries; these three refuse on a `read_only` `Runtime`.
- `read_only` → `Runtime`, as `Fs.read_only`.

Structs `ProcessInfo`, `SourceInfo`, `MemoryInfo`, `Event` (an enum of the kinds above) in the prelude; `Json.encode` of each is the wire form. A corpus file under `examples/effects/runtime.mo` runs a process, asks the surface, and asserts on what it sees, under `mo test`, holding under `--sim`.

## Part C: the on-ramp

`mo run --surface PORT file.mo` (and `MO_SURFACE=PORT` for a binary built with `--surface`) serves the same rows as JSON over HTTP on 127.0.0.1: `GET /processes`, `/state/<id>`, `/recent/<id>?n=`, `/events?since=&n=`, `/crashes?n=`, `/sources`, `/memory`, `/slowest?n=`, and `POST /send/<id>`, `/pause/<id>`, `/resume/<id>`, each answered from the runtime's thread between updates. It is a program's `Http` server the toolchain starts, not a new transport. A `jobq` run with `--surface` must answer the nine questions on d37 where the rows can (the report says which they cannot, and why).

## Part D: numbers

`kv-10k-get`, `http-1k`, their native rows, and jobq's 32-worker lease-and-ack rate before and after with the ring on at 4,096 (must be within 5 percent, or the recording moves off the hot path); the ring's resident memory at 4,096 and at 65,536 events; the time `GET /processes` takes with 10,000 live processes; the nine questions with the answer each got.

## Done when

Green at every commit; the ring in both runtimes and printed on a failed seeded test; `platform.runtime` with the rows in both runtimes and the spec tables; `read_only` refusing the three acts; `--surface` under `mo run` and in a built binary; the corpus file; jobq's nine questions answered or explained; the numbers; pushed; a numbered list "Decisions the brief did not cover".

## Related
- [[d37-runtime-mcp-surface]]
- [[d40-structured-runtime-events]]
- [[program-1]]
- [[interpreter-step-22]]
