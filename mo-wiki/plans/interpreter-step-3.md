---
title: "Interpreter step 3: run the tests, brief for the worker"
created: 2026-09-12
updated: 2026-09-12
type: plan
tags: [compiler, runtime, contracts]
sources: [spec/design-v0/05-verification.md, spec/design-v0/08-milestone.md, spec/grammar.md]
status: done
---

# Interpreter step 3: run the tests, brief for the worker

Steps 1 and 2 gave a parser and a tier-1 checker that handle the whole corpus in about 250 µs. Step 3 is the interpreter: `bytecode.zig`, `vm.zig`, `contracts.zig`, `runner.zig`, `verified.zig`, and `mo test`. After it, every `test` in the corpus runs, every `test rejects` trips its `requires`, `property` blocks run under seeds, and the `verified:` line is computed. Processes and supervisors are step 4; this step runs pure code only.

## Orientation

`toolchain/README.md`, `toolchain/src/` in full (the stubs for this step carry the design in their doc comments; `ast.zig`, `types.zig`, `check.zig` are real now), `toolchain/PRELUDE.md`, `spec/design-v0/03-semantics.md` (values, functions, failure), `05-verification.md`, `08-milestone.md`, and the Session 5 decisions at the foot of `spec/grammar.md`.

## Write scope

`toolchain/` and `examples/`, branch `session-05`, `git pull --rebase --autostash` before every push, one commit per part.

## Part A: the refund module joins the corpus

Copy chapter 4's example to `examples/payments/refund.mo` exactly as written there. Add to the prelude (marked corpus-only, in `PRELUDE.md`) what it needs: `Charge`, `ChargeId`, `Money`, `RefundRequest`, `Charge.fixture`, `Money.cents`, `Money.zero`, `Ledger.find_charge`, `Ledger.save_charge`, `Events.emit`, `RefundCompleted`, `RefundFailed`, `Time`, `t0`. It must pass `mo check`. Its process is not run in this step.

## Part B: bytecode and VM

A stack machine. Values: sized integers, floats, bools, strings, lists, tuples, structs, enum variants, `Option`, `Result`, `Time`, `Duration`, capability fixtures. Value semantics throughout: a `var` is copied on assignment from another name, and `inout` writes back on return. Integer arithmetic traps on overflow in every build; `checked_`, `saturating_`, `wrapping_` are the only other behaviours. A trap is `error.Crash` carrying a `contracts.Report` (what tripped, where, the values involved). One arena per test, freed whole.

## Part C: contracts at tier 2

`requires` checked on entry, `ensures` on exit with `result` and `old(...)` (evaluate `old` operands on entry), refinement `where` checked when a value crosses into a refined parameter, field, or return. Contract expressions evaluate in unbounded integers: use `i128` for now and record in the code that it is a stand-in. `never` and `invariant` are not evaluated in this step (they need `Type.all` and processes). A tripped contract is a crash with a report naming the clause.

## Part D: the test runner and `mo test`

`test` passes when every `assert` holds and nothing crashes. `test rejects` passes only when the body trips a `requires` or a refinement; passing normally, or crashing on anything else, fails it. `property` runs its comprehension under 200 seeds from a fixed base seed, generating `any(T)` for integers, bools, strings, lists, and structs of those; a failure reports the seed and the generated values. Files that declare a `process` have their tests skipped with the reason "processes run in step 4"; `runner.Summary` counts them. `mo test <file>` prints one line per test, the summary, and the `verified:` line from `verified.zig`, which this step extends to `verified: types, contracts, tests (N), property (200 seeds), sim (not run)`. The line is printed, not yet written into the file; writing it and teaching `MO0317` to accept a toolchain-written line come with the sidecar in a later step. `mo run <file>` runs the module's tests too until `main` exists.

## Part E: the corpus test tightens

`pipeline.implemented = .run`. For every non-`rejects/` file: all tests pass, all `rejects` trip, all properties hold, except the six process files, which report skipped. `rejects/` files still fail at check. Add `examples/README.md` a line saying what `mo test` does today.

## Part F: numbers

`zig build bench -- ../examples 20 --record` and `bench/rebuild.sh --record`; the `run` row now means "run every test in the corpus". Chapter 5's tier-2 target is 100 ms per changed function; report the whole-corpus number and the slowest file in the commit message. Do not optimize.

## Also

- `MO0308` on an integer or string scrutinee should say "this case does not cover every UInt32; add a `_` arm" rather than "does not cover `_`".

## Done when

`zig build test` green with `implemented = .run`, `mo test` runs every corpus file and `examples/payments/refund.mo`, the `verified:` line prints, bench rows recorded, pushed. Stop; processes are step 4.

## Related
- [[interpreter-step-2]]
- [[decision-log]]
- [[roadmap]]
