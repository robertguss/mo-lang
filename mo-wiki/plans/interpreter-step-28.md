---
title: "Step 28: what round 7 found in the runtime, brief for the worker"
created: 2026-09-14
updated: 2026-09-14
type: plan
tags: [runtime, performance, stdlib, compiler]
sources: [plans/control-run-7.md, decisions/decision-log.md, plans/interpreter-step-27.md]
status: queued
---

# Step 28: what round 7 found in the runtime

Round 7's Mo worker left four toolchain bug notes and six gaps ([[control-run-7]]). The map write that copies the whole map is the one every program with a growing map pays for; replay is the runtime's slowest path against Go. This step is the runtime's, not the language's: no syntax.

## Orientation

`../mo-lang-control7-mo/examples/programs/jobq/TOOLCHAIN-BUGS.md` and `programs/logstat/TOOLCHAIN-BUGS.md` (the four reproductions), that worktree's `examples/GAPS.md` (the six gaps; evidence, read only, change nothing there), `toolchain/src/vm.zig` and `runtime/mo_rt.c` (values, maps, regions), `bytecode.zig` and `emit_c.zig` (the at-rest rule from step 27, part C), `09-stdlib.md` and `PRELUDE.md` (the `Fs`, `Option`, integer, and `Clock` rows), `sim.zig` (the fixture clock), `bench/` (the `kv` and `reuse-map-*` rows).

## Write scope

`toolchain/`, `examples/`, and the spec rows the parts name in `09-stdlib.md` and `PRELUDE.md`. Branch `session-05`, one commit per part, `Step 28 part X` in the subject, push after every commit, `zig build test` green at every commit.

## Part A: a map written in place

Setting an existing key or removing one copies the whole map in both runtimes (2,000 writes at 80k entries: 22.7 s inside an `update`). A map held by exactly one owner (a `var`, a `state` field, an accumulator) is written in place; a map with another holder is copied once and then written in place. The same for a list's `set` and a struct's field write where the struct is uniquely held, if they copy today. A bench row `map-set-80k` (2,000 overwrites at 80k entries) and `map-remove-80k` before and after, both runtimes; the `reuse-map-*` rows kept.

## Part B: a `reduce` with a tuple accumulator, and the `never` rule's gap

1. A `reduce` whose accumulator is a tuple copies it each step (1,214 ms against 19 ms for a plain accumulator): the accumulator is moved, not copied, in both runtimes. A bench row.
2. The at-rest rule (step 27, part C) still records a `var` copy when the second write sits inside an `if`: the rule looks past a branch to the body's next write of the same root name, so a `var` written in two arms and then again after the `if` is recorded once, at its last write. `contracts/never-var-copy.mo` gains the logstat shape (`+= 1` then `if error: next.errors += 1 end`).

## Part C: resident memory and replay

1. Resident memory grows far past what the regions hold (120 MiB held at 40k jobs against 12 MiB in the regions) and `MemoryInfo` does not see the difference: find where it goes (freed regions not returned, the allocator's retention, mailbox or connection buffers, the C runtime's arenas), fix what is fixable, and make `MemoryInfo` report resident and region bytes both. Numbers at 100k jobs, both runtimes, before and after.
2. Replay of a 1M-record log is 15.3 s native against Go's 4.8 and Python's 5.2: profile the store recipe's replay path (`read_lines` or `fold_lines`, JSON decode, the map writes from part A) and take what part A gives; report the split. A bench row `replay-1m` before and after.

## Part D: the six gaps

1. `Fs.list` tells a file from a folder: an `Entry` with `name` and `kind`, or a `Fs.list_kinds` row, whichever is plainer, with `09-stdlib.md` and `PRELUDE.md` rows.
2. A thousands separator: `n.to_s(grouped: true)` or `String.grouped(n)`, writing `1_204`.
3. An anonymous function may leave a parameter unread by naming it `_`.
4. `seconds` on an integer (`10.seconds`), beside `ms`, `minute`, and `days`; and a wrong unit (`1.second`) is a check-time diagnostic naming the units, not a run-time crash.
5. `Option.map`.
6. A fixture clock that follows the simulator's time: `Clock.fixture()` moves when a fixture wait or a delayed send moves the simulator, so a process test can watch a lease run out; `03-semantics.md` or `09-stdlib.md` says so in one sentence, the worker names which.

Each with a corpus file or an extension of one, under `mo test`, `--sim 100`, and as a test binary.

## Part E: both runtimes and the corpus

The whole suite green; `mo fmt --check` clean; every new row in both runtimes; the bench rows recorded.

## Numbers

`map-set-80k`, `map-remove-80k`, the tuple `reduce` row, `replay-1m`, resident memory at 100k jobs, `kv-10k-get`, `logstat-4k`, before and after, both runtimes.

## Done when

Green at every commit; the map in place with its rows; the tuple accumulator moved; the `never` gap closed with its corpus line; memory accounted for and replay's split reported; the six gaps with their files; the numbers; pushed; a numbered list "Decisions the brief did not cover".

## Related
- [[control-run-7]]
- [[interpreter-step-27]]
- [[decision-log]]
