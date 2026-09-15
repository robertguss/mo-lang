---
title: "Step 30: processes on every core, brief for the worker"
created: 2026-09-15
updated: 2026-09-15
type: plan
tags: [runtime, processes, performance]
sources: [plans/interpreter-step-21.md, plans/interpreter-step-29.md, spec/design-v0/03-semantics.md, spec/design-v0/07-toolchain.md, plans/control-run-7.md]
status: queued
---

# Step 30: processes on every core

Since step 21 every process is a fiber on main's thread, so a Mo program uses one core of four. Processes share nothing and speak only by message, which is the property that makes running them on several threads safe. This step is the runtime's; the language does not change. Written as a sketch on 15 Sep; the brief is finished after step 29 lands, with its Orientation pointing at what step 29 changed.

## The shape to build

A scheduler per core, each running fibers as today; a process belongs to one scheduler for its life (no migration in v1), chosen at `start` by the least loaded; a `send` across schedulers is a lock-free or mutex-guarded push with a wake; `ask` and deadlines unchanged; the poller shared or one per scheduler, the worker chooses and says why; the store's `fsync` off the scheduler thread so one process's flush does not stall the others; `Mo.Sim` unchanged and still deterministic (one thread under `mo test`); the runtime surface reports a process's scheduler; the C runtime the same.

## Measured

The job queue and the ledger under Fable's one client at 32 workers, 1 and 4 cores, native and interpreted; `echo-1k` and `http-1k`; the process-at-rest memory unchanged; 65,530 idle connections still held; the suite's determinism under `--sim` unchanged (the same seed, the same trace).

## Done when

Both runtimes; the numbers; the corpus green; no change to any corpus program's source; pushed; the decisions list.

## Related
- [[interpreter-step-29]]
- [[interpreter-step-21]]
- [[control-run-7]]
