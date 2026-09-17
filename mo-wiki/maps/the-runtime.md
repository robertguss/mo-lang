---
title: "The runtime"
created: 2026-09-16
updated: 2026-09-16
type: map
tags: [runtime, processes]
sources: [index.md, plans/roadmap.md, decisions/decision-log.md]
status: living
---

# The runtime

A map of content for layer 1: the process model, the failure model, the two runtimes and the C backend, and every step that changed them under a program's pressure. The runtime carries the thesis's reliability claim, so this is where most of the measuring happened.

## The model

- [[03-semantics]] — chapter 3: values, functions, effects, processes, the failure model (what a crash discards, what a timeout leaves, what a restart loses), the runtime surface
- [[07-toolchain]] — chapter 7: the interpreter, the compiler, the agent interface, the bets that carry numbers
- [[state-model]], [[errors-and-failure]], [[effects-and-capabilities]] — the deep dives behind chapter 3
- [[d14-processes-are-the-only-identity]], [[d12-concurrency-at-the-edges]], [[d16-direct-style-io]], [[d33-bounded-mailboxes]], [[d36-vm-first-runtime]], [[d37-runtime-mcp-surface]], [[d40-structured-runtime-events]], [[d38-time-travel-debugging]], [[d39-hot-code-reload]]
- [[vm-first-vs-c-first]] and [[agent-native-runtime-features]] — the two deep dives that filed directions 36 to 40
- [[q07-process-api]], [[q18-main-and-the-platform]], [[q11-platform-and-stdlib]]

## The steps, in the order they landed

- [[interpreter-step-4]] — the milestone: `Mo.Sim`, `update` as a transaction, invariants, bounded mailboxes, supervisors, the crash report
- [[interpreter-step-9]] — seeds and faults
- [[interpreter-step-11]] — `Net`, processes under `mo run`
- [[interpreter-step-13]] and [[interpreter-step-15]] — the C backend, then processes and `Net` in it
- [[interpreter-step-16]] — `Http`
- [[interpreter-step-18]] — the outside review's fixes: `invariant` after every update, handles as capabilities, the depth bound
- [[interpreter-step-19]] and [[interpreter-step-20]] — a process that nothing holds ends; the runtime owns the loop
- [[interpreter-step-21]] — memory and green threads: a process is a fiber, 65,530 idle connections
- [[interpreter-step-22]] — the derived deadline, `reply_by`
- [[interpreter-step-23]] — the runtime surface as a capability, structured events
- [[interpreter-step-24]] — a delayed send, handles in state, the read-only `Fs` hole closed
- [[interpreter-step-28]] — writes in place, regions giving pages back
- [[interpreter-step-29]] and [[interpreter-step-29b]] — `restart: :never` honoured; replay memory bounded on a real log
- [[interpreter-step-30]] — a scheduler per core, `fsync` off the scheduler; the Mac table
- [[interpreter-step-31]] — the deferred reply
- [[mac-scaling-run]] — nothing scales on the M3 Max; placement is the next step

## The runtime's own row

A crashed process with the service still answering, P6: [[control-run-8]] (Mo's outage, a wait hidden as a message pattern), [[control-run-10]] (the BEAM restores service in under 600 ms, and exits on the fourth kill or on a full disk), [[erosion-round]] (generation two answers through a full disk in Mo, Go, and Python; Elixir does not), [[10-language-after-the-rounds]] §1 and §2 (what the language should say about it).

## Compilation

- [[d23-compile-speed-first-class]], [[d24-compile-to-c-via-zig]], [[d25-interpreter-for-the-edit-loop]], [[compilation-target-and-compile-speed]], [[q13-implementation-language]]
