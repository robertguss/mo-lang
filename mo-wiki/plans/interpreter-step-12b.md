---
title: "Step 12b: two ratified defaults, undone, brief for the worker"
created: 2026-09-13
updated: 2026-09-13
type: plan
tags: [runtime, verification, laws]
sources: [decisions/decision-log.md, spec/design-v0/02-laws.md, spec/design-v0/05-verification.md]
status: done
---

# Step 12b: two ratified defaults, undone

Two runtime choices a worker made and Fable ratified are being reversed, because each lets a program pass while quietly not meaning what the spec says. Small step, two parts.

## Part A: memoization leaves the reference semantics

Step 7 added a cache of pure-call results under `mo run`. Remove it from the interpreter: the interpreter is the executable reference semantics (chapter 7) and must run every body every time, checking every contract every time. Keep the profiler's finding as a note in the code: speed comes from the C backend (step 13), not from the reference. Re-record the `logstat-4k` and `kv-10k-get` bench rows and put before and after in the commit message; a slowdown is expected and accepted.

## Part B: every `never` runs on every test

A `never` block is evaluated at the end of every `test`, `test rejects`, and `property` run, over the values that run produced, not only under `--sim`. Recording covers structs, enums, and primitives held in any binding, field, message, or state (extend the recorder; the cost is accepted in `mo test`). A `never` over a type the recorder cannot cover is a compile error, `MO0324`, "this never cannot be checked" (chapter 2, contract laws), never a silent skip. The corpus gains `examples/contracts/never-trips.mo`: a `never` that is false on plain test data, with a `test rejects` expecting it, so `mo test` without `--sim` proves the check runs. `verified: contracts` on the line now means `never` was checked.

## Done when

`zig build test` green, the bench rows re-recorded, the new corpus file trips without `--sim`, pushed, decisions listed. Fable updates the decision log rows to `overturned`.

## Related
- [[interpreter-step-12]]
- [[interpreter-step-13]]
- [[decision-log]]
