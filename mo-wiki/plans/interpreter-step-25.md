---
title: "Step 25: the one-line if as a value and keyword field names, brief for the worker"
created: 2026-09-14
updated: 2026-09-14
type: plan
tags: [syntax, tooling, compiler]
sources: [syntax/p16-one-line-if-value.md, spec/grammar.md, plans/control-run-4.md, plans/interpreter-step-21.md]
status: done
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

## Part D: step 24's leftovers

1. `MO0404`'s catalog `what` and `why` say what the diagnostic now says: a narrowed `Fs` (or any narrowed capability) reaching a call that needs the wider one, through a parameter, a start argument, a message field, or a `child` line; the two `rejects/` files from step 24 quote the diagnostic again; and a read-only `Fs` hidden by an `if` expression (`Writer.start(if a fs.read_only else fs end)`) is followed too, with a `rejects/` file.
2. `agent`: a run that does not grant `write` holds a read-only `Fs` again, as the spec says; the writing tool lives in a process started only when the run grants `write`, or the worker finds a shape the checker accepts with the same authority, said in the report.

## Part E: both runtimes and the corpus

The lowering is the block form's; the C backend the same; a corpus test under `mo test` and as a test binary; `mo fmt --check` clean over the corpus after the reformat, in one commit that says what changed.

## Numbers

`lex`, `parse`, `check`, `fmt` bench rows before and after; the count of `if` values in the corpus that the formatter now writes on one line.

## Done when

Green at every commit; the production, the formatter rule, the fix reversed, the three corpus files, the keyword field names with their corpus file and `jobq` on them, `MO0404`'s wording and the `if` hole with its file, `agent` narrowed again, both runtimes, the numbers, pushed, a numbered list "Decisions the brief did not cover".

## Result

Accepted 14 Sep 2026, 13:55 UTC. Written in 95 minutes over two workers: part A on the Mac (08:04 EDT, pushed after the handoff said the worker had exited with nothing), parts F, B, C, D, E on the exe.dev VM by a fresh worker, green at each commit, 184 of 184 at the end. Part F was the lead's addition: the suite's first run on Linux failed three tests (part A's hand-written `verified:` line; a Json unit test reading a slice of its helper's dead stack frame, hidden on the Mac by its stack layout; the `--surface` corpus test picking ports inside Linux's ephemeral range and binding over a `TIME_WAIT` socket), none the poller's. Part A: the production, the tree the block form's, `MO0101` for the statement form, a missing `else:`, and a statement in a branch. Part B: `FORMAT.md` I1–I4, the formatter choosing the shape by width and comments, `mo fix` no longer rewriting it, the corpus reformatted (25 one-line values, from 2). Part C: `state` and `old` as a struct's field in three positions (declared, built, after a dot), `types/keyword-fields.mo`, `rejects/state-binding.mo`, jobq's `status` back to `state` with its hand-built JSON kept for stated reasons and no `.expected` change. Part D: `MO0404`'s catalog wording, the `if` and `case` hole closed with `rejects/read-only-if-argument.mo`, `agent` narrowed to spec 05 again with a `Writer` process only for a run granted `write_file`. Part E: a test that both forms emit the same C and bytecode; `basics/if.mo` with the form as an anonymous function's body, an argument, an arm's value, and inside an interpolation.

Numbers (Linux VM, best of 20, `bench/results.tsv`): lex 7,258 → 6,808 µs, parse 17,140 → 17,201, check 59,800 → 61,180, fmt 9,592 → 9,902 over 145 → 149 files, the new binary on the old corpus matching or beating every row; logstat-4k 105.6 → 104.0 ms interpreted, 12.0 → 13.3 native; kv-10k-get 299 → 292 / 140 → 141; http-1k 35.4 → 37.9 / 31.5 → 34.5.

Fable's probes: a nested one-line `if`, one in a list literal, an argument, parentheses before `*`, and assigned to a `state` field, the same output from `mo run` and the built binary; the statement form, a missing `else:`, and a `return` in a branch refused with sentences that say what to write; `mo fmt` folding a block that fits and unfolding one too long, idempotent; `mo fix` leaving both alone; `Json.encode` of `state` and `old` fields; a read-only `Fs` hidden in a bound block `if` and in a `case` arm refused; agent's check line under `mo run`. One finding: a one-line `if` as a body's last expression is refused as a statement while the block `if` there is the value; Fable's call (tail position is a value) goes to step 26 before round 6. The `var state = n` and `old` parameter refusals carry the parser's bare "expected a name".

## Related
- [[p16-one-line-if-value]]
- [[control-run-4]]
- [[interpreter-step-21]]
