---
title: "Step 24: what program 5 found, brief for the worker"
created: 2026-09-14
updated: 2026-09-14
type: plan
tags: [runtime, processes, effects, stdlib]
sources: [plans/program-5.md, decisions/decision-log.md, spec/design-v0/03-semantics.md, spec/design-v0/09-stdlib.md]
status: in-progress
---

# Step 24: what program 5 found

Program 5 ([[program-5]]) found an authority hole, showed the handle law forcing every request through one process for the third program running, and was the third program to want a timer. Fable's calls are in the decision log of 14 Sep night; this step implements them and closes four gaps. No syntax: `delay:` is a prelude name already, and `none` is a type name already.

## Orientation

`examples/programs/agent/TOOLCHAIN-BUGS.md` and the seven `agent` lines of `examples/GAPS.md`; `examples/programs/agent/registry.mo`, `book.mo`, `mock.mo` (the shapes the calls change); `toolchain/src/caps.zig` (step 18's rules: a handle is a capability, capture and fields refused; step 20's message fields), `check.zig`, `sim.zig`, `turns.zig`, `sources.zig`, `runtime/mo_rt.c`, `prelude.zig`; `spec/design-v0/03-semantics.md` (processes, what a message may carry, the failure model), `09-stdlib.md` (`## Runtime`, `Deadline`, `Fs`); the decision rows of 14 Sep night after program 5.

## Write scope

`toolchain/`, `examples/`, and these spec lines only: the process paragraph of `03-semantics.md` on what a state field may hold and on a delayed send, the `Deadline`, `Event`, and `send` rows of `09-stdlib.md` and `PRELUDE.md`, the `flows` and handle lines of `03-semantics.md` only if the hole's fix needs a sentence; each with a "Session 5, step 24" line. Branch `session-05`, one commit per part, `Step 24 part X` in the subject, push after every commit, `zig build test` green at every commit.

## Part A: the authority hole

A read-only `Fs` (`fs.read_only`, or `fs.scoped(p).read_only`) passed as a process's start argument, then written through inside the process, crashes at run time instead of being refused by `mo check`; the same for a read-only `Fs` handed on in a message field. The checker follows the narrowing into start arguments and message fields as it follows it into a function parameter, and a write through it is the same diagnostic a function gets. A `rejects/` corpus file for the start-argument case and one for the message case; `agent`'s `write_file` backstop comment goes.

## Part B: a handle in a state field

A process's `state` may declare a field of type `Handle(T)`, `Option(Handle(T))`, `List(Handle(T))`, or `Map(K, Handle(T))`; structs, enums, and returned values stay refused as step 18 left them, and a handle still cannot be captured. The runtime counts the handles a state holds as it counts those in start arguments (step 19), so a process held only by another's state is not freed while that process lives, and a crashed process's state releases them. Both runtimes and `Mo.Sim`. A corpus file `examples/processes/registry.mo`: a registry that starts a worker per key, keeps the handles in a map, and routes an `ask` to the right worker; a test that a worker whose key is removed from the map ends (step 19's rule, observable through `Runtime.fixture().processes`). Then `agent`: the registry routes to a process per run through its map where the brief's shape wanted it, if the worker judges the rewrite under an hour; else the corpus file alone, said in the report.

## Part C: a delayed send

`handle.send(Message, delay: Duration)`: the message is delivered no earlier than `delay` after the sending update ends, in order with the process's later sends only after that time; under `Mo.Sim` the seed orders it once simulated time passes; a delayed send held by a crashing update is dropped with the others; a delayed send to a process that has ended is dropped. Both runtimes. The spec sentence in chapter 3's process paragraph. A corpus file `examples/processes/timer.mo`: a process that sends itself a `Tick` on a delay and stops after three, under `--sim`. Then `agent`'s mock and its naps use it instead of an `accept` on a listener nothing connects to, and `jobq`'s lease sweep may use it for expiry if the worker judges it under half an hour; else say so.

## Part D: four gaps

1. `Deadline.remaining` → `Duration`, zero once passed; `agent` uses it where it wrote `by.at_most(0.ms) == by`.
2. `Result(none, E)` is writable in a user signature as the prelude's rows write it.
3. The prelude `Event`'s fields named `process`, `message`, and `state` are renamed off the keywords (the worker chooses; `pid`, `taking`, `snapshot` are fine) so a pattern can take them; the surface's JSON and `examples/programs/surface` follow; `agent`'s operator destructures an event where it parsed JSON.
4. A recipe module's own `Request` (or `Response`, `Event`, `RuntimeError`) is hidden from its implementation as step 23 hides a module's own from every other module; `model-client.mo` and `Agent.Model` stop working around it.

## Part E: the simulator's ask

Under `--sim`, an `ask` that waits delivers a round for every process, not only its target's, so a test polling one process cannot starve another; the fixed order stays the fixed order; `agent`'s test that worked around it is simplified; every `--sim 100` in the corpus still holds.

## Numbers

`kv-10k-get`, `http-1k`, their native rows, jobq's 32-worker rate, and agent's 32-run rate before and after, best of five, nothing over 5 percent slower; the memory of a registry holding 10,000 handles; the delivery lag of a 100 ms delayed send under `mo run` and as a binary.

## Done when

Green at every commit; the two `rejects/` files for part A; the registry corpus file and the handle-counting rule in both runtimes; the delayed send in both runtimes and the simulator with its corpus file; the four gaps with corpus evidence; the simulator's ask; the spec lines; the numbers; pushed; a numbered list "Decisions the brief did not cover".

## Related
- [[program-5]]
- [[interpreter-step-22]]
- [[interpreter-step-23]]
- [[d14-processes-are-the-only-identity]]
