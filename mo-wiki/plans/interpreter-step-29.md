---
title: "Step 29: the runtime honest, brief for the worker"
created: 2026-09-15
updated: 2026-09-15
type: plan
tags: [runtime, processes, errors, compiler]
sources: [plans/program-6.md, spec/design-v0/03-semantics.md, decisions/decision-log.md, plans/interpreter-step-28.md]
status: queued
---

# Step 29: the runtime honest

Program 6 found the runtime not doing what chapter 3 says in two places and holding a whole replay in one update. This step makes the runtime say what it does and do what it says. No syntax.

## Orientation

`examples/programs/ledger/TOOLCHAIN-BUGS.md` (the two reproductions), `examples/GAPS.md` (the simulated-time line from the ledger), `spec/design-v0/03-semantics.md` (the failure model: "say `restart: :never` and mean it", what restart loses, the delayed send), `toolchain/src/vm.zig`, `sim.zig`, `runtime/mo_rt.c` (supervisors, restart, the delayed-send queue, `platform.exit`), `examples/programs/ledger/journal.mo` (`Open` replaying the whole log in one update), `examples/recipes/store.mo`, the `invariant` rows of programs 1, 5, and 6 in the decision log.

## Write scope

`toolchain/`, `examples/`, and the spec lines the parts name in `03-semantics.md` and `09-stdlib.md`. Branch `session-05`, one commit per part, `Step 29 part X` in the subject, push after every commit, `zig build test` green at every commit.

## Part A: `restart: :never` means it

A process whose supervisor line says `restart: :never` stays down after a crash under `mo run`, `mo test`, and as a binary; a message to it afterwards is answered as the failure model says for a down process (an `ask` gets the down outcome within its deadline, a `send` is dropped with an event), and the supervisor's crash report names the child as not restarted. The ledger's reproduction becomes `processes/never-restart.mo` under both runtimes and `--sim`; `03-semantics.md`'s sentence gains "first tested by" it.

## Part B: `platform.exit` with a pending delayed send

`platform.exit(code)` ends the program at once: pending delayed sends are dropped with an event, listeners closed, the exit code kept. The ledger's check data may take its long-lived holds back; a corpus program with a pending `delay:` and an `exit` line under both runtimes.

## Part C: replay streamed

The ledger's `Open` replays 1M entries inside one update and is killed at 4.2 GB native. Either the runtime frees what an update no longer reaches while the update runs (a region that compacts mid-update when a fold's accumulator is the only live value), or the store recipe's replay is a fold whose steps rest between records, whichever the worker judges the runtime's fix rather than the program's, said in the report. Measured: the ledger's 100k, 500k, and 1M replays native, time and peak memory, before and after; the 1M replay must finish in bounded memory.

## Part D: simulated time and the untrippable invariant

1. Under `mo test`, simulated time jumps to the next delayed send at every statement boundary, so an hour-long hold expires between two statements: time moves to a delayed send only when a test waits (a fixture call with a delay, an `ask` whose deadline passes, an explicit wait), never at a bare statement boundary; the ledger's gap line closes with a corpus test.
2. An `invariant` that no message can break is documentation with a keyword (three programs kept none, or kept one against the spec's rule): `mo test --sim` reports, for each invariant, whether any seed's message tripped it in a `test rejects`, and `mo check` gains nothing; the report goes in the `verified:` line's sim clause as `invariants (kept n, tripped m)`. No new syntax.

## Part E: both runtimes and the corpus

Every changed file under `mo test`, `--sim 100`, and as a test binary; the ledger's five run lines identical under both runtimes; `mo fmt --check` clean; the whole suite green.

## Numbers

The ledger's replay rows (100k, 500k, 1M) native, time and peak memory, before and after; `kv-10k-get`, `http-1k`, `logstat-4k` unchanged within noise; the ledger's transfers a second at 32 clients unchanged within noise.

## Done when

Green at every commit; a `:never` child stays down in both runtimes with its report; `exit` ends a program with a pending delayed send; the 1M replay finishes native in bounded memory; simulated time moves only when a test waits; the `verified:` line counts invariants tripped; the numbers; pushed; a numbered list "Decisions the brief did not cover".

## Related
- [[program-6]]
- [[interpreter-step-28]]
- [[interpreter-step-30]]
- [[decision-log]]
