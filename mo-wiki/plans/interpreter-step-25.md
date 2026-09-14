---
title: "Step 25: the one-line if as a value and keyword field names, brief for the worker"
created: 2026-09-14
updated: 2026-09-14
type: plan
tags: [syntax, tooling, compiler]
sources: [syntax/p16-one-line-if-value.md, spec/grammar.md, plans/control-run-4.md, plans/interpreter-step-21.md]
status: queued
---

# Step 25: the one-line `if` as a value

Robert's call (14 Sep, morning): add the form round 4 lost two loops to. [[p16-one-line-if-value|Pick 16]] states the rules. This is the first grammar addition since step 18's grouped patterns; it is one production, the formatter's rule, the fix's reversal, and the corpus.

## Orientation

`spec/grammar.md` (§ expressions, `if` as expression at line 111; the arm production at 85), `toolchain/src/parser.zig`, `fmt.zig` and `FORMAT.md` (rules C1 and C3, the arm form this mirrors), `fix.zig` and the `MO0101` fix step 21 added, `errors.zig`, `examples/basics/if.mo`, `examples/rejects/` (the step 21 file for the one-line `if`), `plans/control-run-4.md` (the two loops).

## Write scope

`toolchain/`, `examples/`, and these spec lines only: the expression production in `grammar.md` with a "Session 5, step 25" line, and the `if` sentence of `04-syntax.md`; `FORMAT.md` gains its rule. Branch `session-05`, one commit per part, `Step 25 part X` in the subject, push after every commit, `zig build test` green at every commit.

## Part A: the grammar and the parser

`"if" expr ":" expr "else" ":" expr` as an expression only; `else:` required; a branch is one expression, and a statement there (`return`, a binding, an assignment) is `MO0101` with a message that says so. A one-line `if` as a statement stays refused with step 21's message, now saying the form is a value only. `examples/basics/if.mo` gains the form; a `rejects/` file for the statement form and one for a missing `else:`.

## Part B: the formatter and the fix

`FORMAT.md`: the one-line value form stays on one line when it fits the limit and no comment sits inside, and otherwise becomes the block form (as C1 and C3 for arms); the idempotence and round-trip tests over the corpus hold. `mo fix` no longer rewrites the value form; the catalog row's fix goes; `zig build errors` regenerated.

## Part C: a keyword as a field name

Robert's second call (14 Sep, morning): `state` and `old` may name a field after a dot (`job.state`) and in a struct's field declaration (`state: String`), and nowhere else; a bare `state` is still the process's state and a bare `old` still the contract's. The lexer keeps them keywords; the parser accepts them in those two positions only. `Json.encode` of a struct with such a field writes the key as named. A corpus file under `examples/types/` with a struct holding `state` and `old` fields, read after a dot and encoded; `jobq/job.mo` renames `status` back to `state` and drops its hand-built JSON where that was the only reason for it, `.expected` files updated with a sentence in the commit; a `rejects/` file for a bare `state = 1` binding.

## Part D: both runtimes and the corpus

The lowering is the block form's; the C backend the same; a corpus test under `mo test` and as a test binary; `mo fmt --check` clean over the corpus after the reformat, in one commit that says what changed.

## Numbers

`lex`, `parse`, `check`, `fmt` bench rows before and after; the count of `if` values in the corpus that the formatter now writes on one line.

## Done when

Green at every commit; the production, the formatter rule, the fix reversed, the three corpus files, the keyword field names with their corpus file and `jobq` on them, both runtimes, the numbers, pushed, a numbered list "Decisions the brief did not cover".

## Related
- [[p16-one-line-if-value]]
- [[control-run-4]]
- [[interpreter-step-21]]
