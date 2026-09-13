---
title: "Step 19: what program 4 found, brief for the worker"
created: 2026-09-13
updated: 2026-09-13
type: plan
tags: [runtime, processes, compiler, stdlib, contracts]
sources: [plans/program-4.md, decisions/decision-log.md, spec/design-v0/03-semantics.md, spec/design-v0/06-packages.md]
status: in-progress
---

# Step 19: what program 4 found

Program 4 ([[program-4]]) found two runtime facts that rule out a shape every server wants, a gap in the package story, and five smaller things. This step fixes them before program 1, the job queue, which wants a process per job.

## Orientation

`examples/programs/notes/TOOLCHAIN-BUGS.md` (two reproductions with numbers), the seven `notes` lines of `examples/GAPS.md`, `spec/design-v0/03-semantics.md` (processes, the failure model), `06-packages.md` (recipes), `toolchain/src/sim.zig`, `turns.zig`, `server.zig`, `runtime/mo_rt.c` (the scheduler in both runtimes), `check.zig`, `caps.zig`, `runner.zig`, `contracts.zig`, the process rows of the decision log (steps 4, 11, 12, 15, 18, program 4).

## Write scope

`toolchain/`, `examples/`, and these spec lines only: the process paragraph of `03-semantics.md` that says how a process ends, the recipe production in `grammar.md` and the recipe paragraph of `06-packages.md`, the `Fs` rows of `09-stdlib.md` and `PRELUDE.md`; each with a "Session 5, step 19" line. Branch `session-05`, one commit per part, push after every commit.

## Part A: a finished process is freed

A process that no live process or `main` holds a handle to, whose mailbox is empty, and that no supervisor names by a `child` line, ends: its thread and memory are freed, in both runtimes. Handles are values; count them across the deep copies messages make. The reproduction in `TOOLCHAIN-BUGS.md` must run 200,000 iterations flat in memory; record the numbers and the cost of the counting on `kv-10k-get` and `http-1k`. Then `examples/effects/http.mo`'s shape, a worker per exchange, must serve 20,000 requests; put that as a program in `examples/programs/` with a `# run:` line the corpus test can afford.

## Part B: the held-send deadlock is a crash, not a hang

When an `update` waits (`ask`, `accept`, `read_line`) on something that can only arrive after a send this same `update` holds, the runtime crashes the process with a report naming the held message and the call, in both runtimes; a `test rejects` in the corpus proves it. Chapter 3's sentence stays; the report is the fix.

## Part C: recipes that cannot drift

A `recipe` may hold `never` blocks (grammar). `mo check --recipe Module.Recipe file.mo` checks that `file.mo` exposes every signature the recipe declares, with the same types and contracts, and runs the recipe's tests and `never`s against the module; a mismatch is a new `MO03xx`. The corpus test runs it for `notes`'s two implementations against their recipes. Chapter 6's sentence about checking gains the command.

## Part D: `Fs.mkdir` and a fixed clock

`Fs.mkdir(path, within:)` with fixture and faults, both runtimes, in the spec rows. `mo run --clock <ISO-8601>` starts `main`'s clock there and advances it with the wall, so a real-socket transcript is the same twice; `notes check` may then stop masking timestamps if the worker judges it worth the edit.

## Part E: three diagnostics and one dead row

`x or default` on a `Result` says that `or` is for `Option` and to write a `case`; importing a message says to import the process; a struct and a variant sharing a name says so. `Fs.each_line` is removed (its callback can reach nothing since step 18) and the two tables say `fold_lines`. Regenerate the catalog.

## Part F: mutation tests of the contract machinery

A test in `toolchain/` that takes three corpus files with `never`, `ensures`, and `invariant` blocks, applies mutants (a witness omitted, an error returned always, a `never` body inverted), and asserts each mutant is caught by `mo test`; record any mutant that survives as a bug in the report.

## Done when

Green, the reproduction flat at 200,000 processes, the deadlock a report, `--recipe` in the corpus test, `mkdir` and `--clock`, three sentences, `each_line` gone, the mutation test with its survivors listed, pushed, decisions listed.

## Related
- [[program-4]]
- [[interpreter-step-18]]
- [[d34-packages-are-recipes]]
