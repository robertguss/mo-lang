---
title: "Step 17: the round 3 follow-ups, brief for the worker"
created: 2026-09-13
updated: 2026-09-13
type: plan
tags: [tooling, stdlib, contracts, laws]
sources: [plans/control-run-3.md, decisions/decision-log.md, spec/design-v0/05-verification.md]
status: done
---

# Step 17: the round 3 follow-ups

Round 3 of the control run ([[control-run-3]]) found two toolchain bugs, one stdlib gap, and six diagnostics that each cost the worker a run. This step fixes all of it before program 4 builds on the same rows.

## Orientation

`git show control3-mo:examples/programs/logstat/TOOLCHAIN-BUGS.md` and `git show control3-mo:examples/GAPS.md` (the worker's reproductions; the branch is evidence, do not check it out), `toolchain/src/runner.zig` (properties), `stdlib.zig` and `runtime/mo_rt.c` (the `Fs` rows), `diag.zig` and the diagnostic tables, `spec/design-v0/05-verification.md` (refinements are contracts), `09-stdlib.md` `## Files`.

## Write scope

`toolchain/`, `examples/`, and the `## Files` rows of `spec/design-v0/09-stdlib.md` and `toolchain/PRELUDE.md`; branch `session-05`, one commit per part, push after every commit.

## Part A: `any(T)` honours refinements

A property over a refined type (`type Percent = UInt32 where ...`) generates only values the refinement admits, in both runtimes. Generate the base type and keep what passes; when fewer than one candidate in a hundred passes, generate from the refinement's bounds where it is a range (`x <= 100`), and when nothing passes after 200 candidates, a new diagnostic in the `MO03xx` range says the property's refinement admits none of the generated values. A corpus file `contracts/property-refined.mo` proves it: a property over `Percent` that would fail on 65,535.

## Part B: `NotText`

A `String` is UTF-8. `Fs.read`, `read_lines`, and `each_line` return `Error(NotText)` for a file that is not, `NotText` added to `FsError` and to the rows in `09-stdlib.md` and `PRELUDE.md`; `Fs.read_bytes(path, within:) : Result(Bytes, FsError)` if `Bytes` exists, otherwise a `List(UInt8)`, so a program that wants the bytes has a row that says so. Fixtures and `Mo.Sim` faults as the other rows. Both runtimes. A corpus test with a file holding a bad byte.

## Part C: a fold over lines

`Fs.fold_lines(path, init, fn(acc, line) : acc, within:)`, the streaming form of `read_lines` that keeps a value, in both runtimes, in the spec and prelude tables, with a stdlib test. Then rewrite `examples/programs/logstat/stats.mo` on `session-05` (the round 2 program, not round 3's) only if it reads whole files; otherwise leave it.

## Part D: six diagnostics reworded

The run tripped `MO0102` (`assert` as a `case` arm expression), `MO0212` (a one-field variant matched by name), `MO0002` (a line wrapped inside a string), `MO0101` (an assignment on a one-line `case` arm; "expected the end of the line" at the `=`), `MO0309` (a `_` arm on a closed type), `MO0317` (a stale `verified:` line). For each, read the worker's account in its report on `control-run-3.md` and make the sentence say what to write instead, in the style of the catalog; `MO0101` must say that a `case` arm holds one expression and a statement goes on its own lines. Regenerate `spec/errors.md`.

## Done when

Green, the corpus proves A and B, the three rows in the spec, six sentences changed, pushed, decisions listed.

## Related
- [[control-run-3]]
- [[interpreter-step-16]]
- [[interpreter-step-14]]
