---
title: "Interpreter step 2: the tier-1 checker, brief for the worker"
created: 2026-09-12
updated: 2026-09-12
type: plan
tags: [compiler, laws, types]
sources: [spec/design-v0/02-laws.md, spec/design-v0/05-verification.md, spec/grammar.md]
status: in-progress
---

# Interpreter step 2: the tier-1 checker, brief for the worker

Step 1 gave us a parser that accepts all 50 corpus files in about 100 µs. Step 2 is `check.zig` and `caps.zig`: tier 1 of `design-v0/05-verification.md`, the stage that makes the 12 files in `examples/rejects/` fail and the other 38 pass. Target: the whole corpus checked in under 50 ms.

## Orientation

`toolchain/README.md`; `toolchain/src/` (the parser and ast are now real: read `ast.zig` fully); `spec/design-v0/02-laws.md`, `03-semantics.md`, `05-verification.md`; `spec/grammar.md` including every Session 5 decision at its foot; `examples/GAPS.md`.

## Write scope

`toolchain/` and `examples/` only, branch `session-05`, `git pull --rebase --autostash` before every push, one commit per part.

## Part A: the prelude

The corpus uses stdlib types and functions that Mo does not yet define anywhere in code: `Int8`…`UInt64`, `Float32`, `Float64`, `Bool`, `String`, `List(T)`, `Option(T)`, `Result(T, E)`, tuples, `Time`, `Duration`, the capabilities `Clock`, `Fs`, `Events`, `Ledger`, their `fixture` constructors, and the names listed under "Stdlib names the corpus may assume" in `grammar.md`. Put their signatures in `toolchain/src/prelude.zig` as data (name, parameter types, return type, whether the call can wait), and list every one in `toolchain/PRELUDE.md` in a table. Nothing outside that table exists. If a corpus file needs a name that is not there and not in the grammar's list, add it to `examples/GAPS.md` and to the table marked "corpus-only".

## Part B: names and types

Name resolution (module scope, `use` imports, `expose` names declared exactly once), then types: inference inside bodies with literals typed from use, declared at every signature, generics with `where` bounds, refinement types checked at boundaries (the boundary check itself is tier 2; tier 1 only types them), `Self` in traits, `try` across error enums by variant name and fields, dot calls as first-argument sugar, `is` patterns binding names into the scope the decisions describe. Every finding is a `diag.Record` with a stable `MO02xx` code.

## Part C: the laws

Everything in chapter 2 that needs no runtime, each with its own code (`MO03xx`): body over 70 lines, file over 500, more than 6 parameters, nesting over 3, state over 12 fields; rebinding; unused binding; `case` not exhaustive or a catch-all `_` arm on a closed enum; a `Result` or `Option` not consumed; a `requires` without a `test rejects`; a default parameter; an anonymous function stored or returned; a `var` captured by an anonymous function or passed to a process; a process not under any supervisor; a hand-written `verified:` line; a `use` cycle.

## Part D: capabilities

`caps.zig`: a function is pure unless it takes a capability parameter; a capability call that can wait must pass `within:`; capabilities flow only through parameters and narrowing; `flows(T, into: Cap)` is checked as "no value of type T reaches a call on Cap" through direct data flow (a struct field counts; tier 1 does not chase through collections, record that limit in the code). Codes `MO04xx`.

## Part E: the corpus test tightens

`pipeline.implemented = .check`. Every `rejects/` file's `# expect error:` comment becomes `# expect MO0xxx: sentence`, and `corpus.zig` asserts the rejected file's first diagnostic carries that code. All 38 other files pass with zero diagnostics. `mo check` prints diagnostics as prose and, with `--json`, as one JSON record per line.

## Part F: numbers

`zig build bench -- ../examples 20 --record`, `bench/rebuild.sh --record`. Check row and rebuild time in the commit message. If check is over 50 ms for the corpus, say so and stop; do not optimize.

## Done when

`zig build test` green with `implemented = .check`, all 12 `rejects/` rejected with their named code, all 38 others clean, `PRELUDE.md` complete, bench rows recorded, pushed. Stop; do not start the bytecode.

## Related
- [[interpreter-step-1]]
- [[corpus]]
- [[decision-log]]
