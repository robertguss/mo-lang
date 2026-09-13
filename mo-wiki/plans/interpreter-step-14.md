---
title: "Step 14: the follow-ups from round 2 and the C backend, brief for the worker"
created: 2026-09-13
updated: 2026-09-13
type: plan
tags: [tooling, stdlib, compiler, laws]
sources: [plans/control-run-2.md, plans/interpreter-step-13.md, decisions/decision-log.md]
status: in-progress
---

# Step 14: the follow-ups from round 2 and the C backend

Small items, each one line in the decision log, together one short step.

## Write scope

`toolchain/`, `examples/`, the generated `mo-wiki/spec/errors.md`, and rows in `mo-wiki/spec/design-v0/09-stdlib.md`. Branch `session-05`, one commit per part, push after every commit.

## Part A: contracts run in every build (overturns a step 13 default)

Chapter 3: "Contracts run in every build." `mo build` compiles `requires`, `ensures`, `invariant`, refinements, and `never` in, on by default. `--no-contracts` turns them off for a measurement and prints a one-line warning to stderr at build time; `MO_CONTRACTS` stays as the run-time override. Re-record `logstat-4k-c` with contracts on and keep the off number as `logstat-4k-c-nocontracts`. The differential test builds with contracts on.

## Part B: three suspected interpreter panics, reproduced or dismissed

Ordering a NaN, parsing an integer of 39 or more digits, `checked_mul` of two huge `UInt64`s. Write each as a corpus test; whichever panics the interpreter is fixed in the interpreter so that it gives the runtime's ordinary result; the C runtime is then checked against it.

## Part C: the formatter, from round 2

A long list literal breaks after commas inside `[` `]` the same way calls break inside parens, one element per line when it does not fit; a one-line anonymous function inside a long call stays one line and the call breaks around it; a nested call is never split across lines by itself. Add the round 2 worker's three shapes as fmt tests. `FORMAT.md` updated.

## Part D: stdlib rows, from round 2

`sort_by(fn(x) key end, descending: true)`? No named-argument booleans on stdlib rows: add `sort_by_desc(fn)`; `min_of(a, b)` and `max_of(a, b)` on orderable values; `Fs.read_lines_each(path, within:, fn(line) ... end)`? Anonymous functions are call arguments, so a streaming read is `Fs.each_line(path, within:, fn(line) ... end) : Result(none, FsError)` where the body is run per line and returns nothing. Rows in `09-stdlib.md`, tests in `examples/stdlib/`.

## Part E: housekeeping

`build` in the `usage:` text; `zig build errors` regenerated (`MO0404`'s new sentence); `PRELUDE.md` and `09-stdlib.md` say `read_only` gives a read-only `Fs` type refused at a write; `mo build` notes in the README; `TOOLCHAIN-BUGS.md` files closed out where fixed.

## Done when

Green, rows recorded, pushed, decisions listed.

## Related
- [[interpreter-step-13]]
- [[control-run-2]]
- [[decision-log]]
