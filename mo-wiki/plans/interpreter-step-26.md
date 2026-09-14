---
title: "Step 26: the one-line if in tail position, and two keyword diagnostics, brief for the worker"
created: 2026-09-14
updated: 2026-09-14
type: plan
tags: [syntax, compiler, tooling]
sources: [plans/interpreter-step-25.md, syntax/p16-one-line-if-value.md, decisions/decision-log.md]
status: queued
---

# Step 26: the one-line `if` in tail position

What step 25's acceptance found, done before round 6 measures the grammar. Small: one parser rule, two diagnostics, the corpus.

## Orientation

`toolchain/src/parser.zig` (`oneLineIf`, the statement-start refusal from part A), `checker.zig` (`MO0310`, a dropped pure value; `MO0201`), `errors.zig`, `examples/rejects/one-line-if-statement.mo`, `rejects/state-binding.mo`, `basics/if.mo`, `plans/interpreter-step-25.md` (its Result), [[p16-one-line-if-value|pick 16]].

## Write scope

`toolchain/`, `examples/`, and one spec line: the `if` sentence of `04-syntax.md` if it says a line-start `if` is a statement. Branch `session-05`, one commit per part, `Step 26 part X` in the subject, push after every commit, `zig build test` green at every commit.

## Part A: tail position is a value

Fable's decision (decision log, 14 Sep, "for Robert"): the one-line `if` is an expression everywhere. Where it starts a line as the last expression of a function body, a `case` arm, an anonymous function's body, or an `update` arm, it is that body's value, exactly as the block `if` there is. Where it starts a line and is not last, it is a dropped pure value, `MO0310`, whose sentence says to bind it or write the block form; it is never a statement, and step 25's `MO0101` sentence for the statement form is kept for a branch that holds a statement. `rejects/one-line-if-statement.mo` moves its `if` mid-body so it still breaks exactly that law; `basics/if.mo` gains a function whose body is one one-line `if` (`fn sign(n: Int32) : String` / `if n < 0: "negative" else: "not negative"` / `end`), under `mo test` and as a test binary. `FORMAT.md` needs no new rule: the formatter's I1–I4 apply to the value where it sits.

## Part B: two keyword diagnostics

`var state = n`, `state` as a parameter, and `old` as a parameter or a binding fall to the parser's bare "expected a name" (`MO0101`). Each gets the sentence `rejects/state-binding.mo` carries in spirit: the word is a keyword, name the process's state or the contract's old value, and a struct's field may take it after a dot; a binding or parameter takes another name. A `rejects/` file for `var state` and one for an `old` parameter, each quoting the diagnostic.

## Part C: both runtimes

The corpus test over the changed files under `mo test`, `--sim 100`, and as `--tests` binaries; `mo fmt --check` clean; `zig build errors` regenerated.

## Numbers

`lex`, `parse`, `check` bench rows before and after (the parser changes); the count of one-line `if` values in the corpus.

## Done when

Green at every commit; the tail-position value in both runtimes with its corpus line, the reject file moved, the two diagnostics with their files, the numbers, pushed, a numbered list "Decisions the brief did not cover".

## Related
- [[interpreter-step-25]]
- [[p16-one-line-if-value]]
- [[decision-log]]
