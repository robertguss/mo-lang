---
title: "Interpreter step 4: processes and supervisors, brief for the worker"
created: 2026-09-12
updated: 2026-09-12
type: plan
tags: [compiler, processes, runtime]
sources: [spec/design-v0/03-semantics.md, spec/design-v0/08-milestone.md, spec/grammar.md]
status: done
---

# Interpreter step 4: processes and supervisors, brief for the worker

Step 3 runs every pure test in the corpus and the refund module, with contracts at tier 2, in about half a millisecond. Step 4 completes the milestone in `design-v0/08-milestone.md`: processes, supervisors, `invariant`, `send`, `ask`, bounded mailboxes, and the `Mo.Sim` scheduler, so the six `processes/` files and the refund queue run their tests.

## Orientation

`toolchain/README.md`, `toolchain/src/` in full (`vm.zig`, `runner.zig`, `contracts.zig` are real; read how a test runs and how a crash is reported), `toolchain/PRELUDE.md`, `spec/design-v0/03-semantics.md` (processes, failure), `08-milestone.md`, the Session 5 decisions in `spec/grammar.md` (processes, supervisors, sibling handles), `directions/d14-processes-are-the-only-identity.md` and `d33-bounded-mailboxes.md` for the reasoning.

## Write scope

`toolchain/` and `examples/`, branch `session-05`, `git pull --rebase --autostash` before every push, one commit per part.

## Part A: the scheduler (`sim.zig`)

`Mo.Sim` is a deterministic scheduler inside the test runner. `Name.start(args)` creates a process with its `state` at zero values (or the `= expr` initializers), returns a `Handle`. `h.send(Msg)` appends to the target's mailbox and returns at once. Mailboxes drain in order, one `update` per message; a test's `send`s are delivered before the test's next statement runs, so a test reads consistent results. `h.ask(Msg, within: d)` runs the target's pending messages then this one, and returns `Ok(reply)` where the reply is the value of the message's arm; `Error(Timeout)` when the target's fixture delay exceeds `d`, `Error(Down)` when the target has crashed and not been restarted. Messages from one sender arrive in order. Green threads are not needed: everything runs on one thread in a fixed order. `clock.now` is frozen for the whole `update`.

## Part B: `update` as a transaction

`state` is a `var` for the duration of `update`. On a crash inside `update` (contract, overflow, `invariant`) the state writes and buffered outgoing `send`s and `emit`s of that message are discarded. `invariant` blocks run after every `update` with `old(state.x)` bound to the value before the message; the block is true when broken, so true is a crash. A mailbox at its bound crashes the **sender** (`mailbox: N`, default 1_000) with a report naming both processes.

## Part C: supervisors

A `supervisor` declaration with parameters and `child Name(args), restart: :always | :on_crash | :never, max_restarts: n per d`. A test may `start` a process directly; the runner is then its supervisor with `:always`. On a crash the child restarts from its initial state; beyond `max_restarts` within the window the supervisor itself crashes and the test fails. The crash report is chapter 3's: seed, the message log up to the crash, the state snapshot before the message, the violated clause.

## Part D: the corpus and the refund queue

The six `processes/` files run their tests; no test is skipped for a process reason any more. Add to `examples/payments/refund.mo` one test that starts `RefundQueue` with fixtures, sends `Enqueue` twice and `Drain`, and checks `done` with an `ask`; add `message Done : UInt32` to the process for that. Check that chapter 4's `invariant "done never goes backwards"` trips when it should: add `examples/processes/invariant-trips.mo` under `rejects/`? No: a tripped invariant is a runtime crash, not a compile error, so add it as a positive file whose `test rejects` expects the invariant to trip (`rejects` now passes on a tripped `requires`, refinement, or `invariant`). Recipe tests stay skipped.

## Part E: the corpus test and `mo test`

`implemented` stays `.run`; the corpus test now expects zero process skips. `mo test` prints the crash report for a failed process test. The `verified:` vocabulary stays `sim (not run)`: simulation with fault injection and seeds is the next step, not this one.

## Part F: numbers

`zig build bench -- ../examples 20 --record`, `bench/rebuild.sh --record`. The `run` row now includes process tests; name the slowest file in the commit message.

## Done when

`zig build test` green with no process skips, the refund queue test passes, the invariant file trips as expected, bench rows recorded, pushed. Then write, in the final message only, the list of every decision you made that the brief did not cover; do not write to `mo-wiki/`.

## Related
- [[interpreter-step-3]]
- [[d14-processes-are-the-only-identity]]
- [[d33-bounded-mailboxes]]
- [[decision-log]]
