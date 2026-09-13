---
title: "Step 9: Mo.Sim with seeds and fault injection, brief for the worker"
created: 2026-09-13
updated: 2026-09-13
type: plan
tags: [runtime, verification, processes]
sources: [spec/design-v0/05-verification.md, spec/design-v0/03-semantics.md, directions/d33-bounded-mailboxes.md]
status: done
---

# Step 9: `Mo.Sim` with seeds and fault injection

Tier 3 of chapter 5 begins: the same process tests, run under many seeds with the scheduler's order and the platform's failures chosen by the seed. `sim (N runs)` on the `verified:` line becomes real.

## Orientation

`toolchain/src/sim.zig`, `runner.zig`, `contracts.zig`, `verified.zig`; `spec/design-v0/05-verification.md` (tier 3), `03-semantics.md` (processes, failure), `directions/d33-bounded-mailboxes.md`; the process files in `examples/processes/` and `examples/payments/refund.mo`.

## Write scope

`toolchain/` and `examples/`, branch `session-05`, one commit per part, push after every commit.

## Part A: seeded scheduling

`mo test --sim N file.mo` runs every test that starts a process N times (default 100) under seeds derived from a base seed (`--seed S`, default from the file's hash so runs are reproducible). Per seed the scheduler chooses: delivery order among processes with pending messages (fair but random), whether a `send` batch is delivered before or after the test's next statement, and the simulated clock's advance per `update` (0 to 10 ms). Tests must hold under every order; a failure prints the seed and the interleaving as a message list.

## Part B: fault injection

Per seed, each capability fixture can fail: `Fs.read` returns `Timeout` or `Missing` with a per-call probability from the seed (default 5%), `Ledger` calls the same, `clock.now` jumps forward by up to the deadline. `ask` may time out. A test may declare `sim never fails` … no: no new syntax. Instead, the corpus keeps two kinds of process tests: those that hold under faults (the queue counts what it drained, whatever failed) and those that assume none (`test` blocks are run under faults only with `--sim`; a test that needs a fault-free world is a design smell and is reported as "passes only without faults"). Record the count of each in the summary.

## Part C: `never` and `invariant` under sim

`never` blocks over `Type.all` are evaluated at the end of every simulated run over every value of that type the run produced (the runner records constructions). A `never` that trips prints the seed and the two values. `invariant` already runs after every `update`.

## Part D: the `verified:` line

`sim (N runs)` when `--sim N` passed with zero failures; `sim (not run)` otherwise. `mo test` without `--sim` stays fast. Add `--sim 100` to the corpus test for the process files and refund.mo; they must hold, or the corpus file is fixed to hold and the fix is explained in the commit.

## Part E: numbers

A `sim-100` bench row: refund.mo under 100 seeds.

## Done when

`zig build test` green with the process corpus under 100 seeds, a deliberately racy process file under `rejects/`? No: a racy process is a runtime finding, so add `examples/processes/racy.mo` whose test fails under `--sim` and passes without, and make the corpus test assert exactly that. Bench rows, pushed, decisions listed.

## Related
- [[interpreter-step-8]]
- [[d33-bounded-mailboxes]]
- [[decision-log]]
