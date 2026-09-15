---
title: "Step 29: the runtime honest, brief for the worker"
created: 2026-09-15
updated: 2026-09-15
type: plan
tags: [runtime, processes, errors, compiler]
sources: [plans/program-6.md, spec/design-v0/03-semantics.md, decisions/decision-log.md, plans/interpreter-step-28.md]
status: done
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

## Result

Accepted 15 Sep 2026, 07:20 UTC, for parts A, B, D, and E, and for part C's speed; part C's memory bound is open, to [[interpreter-step-29b]]. Five commits (A–E), green at each, the suite green at the end, `mo fmt --check` clean; about 2 h 47 min of worker time, most of it the five-run measurement series. Part A: `Name.start` takes its whole policy from the first child line naming it (only `max_restarts` before), a `:never` child stays down with its report ending "not restarted", asks `Down`, sends dropped with `Event.Dropped`. Part B: `exit` ends the program when `main` returns, delayed sends dropped with events, the ledger's check holds live an hour again. Part C: the runtime's fix, `reduce` and `fold_lines` compacting in generations in both runtimes. Part D: simulated time moves only in a wait or at a test's end; `--sim` reports each invariant kept or tripped and the `verified:` line counts them. Part E: the bench.

Numbers (the worker's, best of five, native unless said, before → after): replay 100k 35.4 → 7.8 s (195 → 203 MiB), 500k 260.5 → 35.6 s (1,138 → 1,087 MiB), 1M 715.6 → 81.2 s (2,485 → 2,490 MiB), 100k interpreted 511.5 → 169.2 s; logstat-4k, kv-10k-get, http-1k within noise; the ledger's transfers a second at 32 clients 1,247 → 1,264. Peak memory is now the book's own size, about 2.5 KB an entry, linear in the log; before, it grew faster than the log and the worker's generated log did not reach program 6's 4.2 GB kill.

Fable's probes, none the brief named: a supervisor with a `:never` child and an `:always` sibling crashed the same way, under `mo run`, as a binary, under `mo test`, and under `--sim 100`, the one down for good and the other back empty, only the one's report saying "not restarted"; `exit(5)` past two delayed sends hours away, 0.00 s and code 5 under both runtimes; a five-minute message pending across three statements and arrived after a fixture wait, under `mo test`, `--sim`, and as a test binary; the journal's `invariants (kept 4, tripped 3)`; Fable's own 100k-entry log driven over HTTP replayed native in 5.0 s at 200 MiB, three runs; and the same session's log at 1M entries (701 MB, 200 accounts) replayed native to 1,111 MiB at 75 s and 8,163 MiB at 90 s, killed past 9 GB at 101 s, after the fold ended and `rebuilt` began, where the live server that wrote it sat at 1,586 MiB: the brief's memory bound is unmet on a real log, to step 29b. Found: a `test rejects` whose process crashes on an overflow fails rather than passes (a row, open). Left: on Fable's real log the replay's peak is not the book's, it is a phase after the fold, and that is step 29b.

## Related
- [[program-6]]
- [[interpreter-step-28]]
- [[interpreter-step-30]]
- [[decision-log]]
