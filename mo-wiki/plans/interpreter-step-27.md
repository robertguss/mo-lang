---
title: "Step 27: what round 6 found, brief for the worker"
created: 2026-09-14
updated: 2026-09-14
type: plan
tags: [laws, syntax, contracts, compiler]
sources: [plans/control-run-6.md, spec/design-v0/02-laws.md, decisions/decision-log.md]
status: done
---

# Step 27: what round 6 found

Robert's three calls of 14 Sep afternoon, on [[control-run-6]]'s reading, and the small items its Mo worker recorded. Chapter 2's "Session 6 changes" states the rules; this brief builds them.

## Orientation

`spec/design-v0/02-laws.md` (the shape laws and the contract laws, and "Session 6 changes"), `spec/grammar.md` (the keyword list at line 17, `old` and `result` at 70 and 115), `spec/design-v0/04-syntax.md` (the struct-change idiom at line 147, the `never` sentence at 140), `toolchain/src/lexer.zig`, `parser.zig` (step 25's field positions, step 26's keyword sentence), `check.zig` (`MO0302`; how a run records values for `T.all`), `vm.zig` and `runtime/mo_rt.c` (where values are recorded), `errors.zig`, `examples/rejects/` (the `MO0302` file, `state-binding.mo`, `var-state.mo`, `old-parameter.mo`), `../mo-lang-control6-mo/examples/programs/logstat/TOOLCHAIN-BUGS.md` and `jobq/TOOLCHAIN-BUGS.md` (the three reproductions, read only, that worktree is evidence).

## Write scope

`toolchain/`, `examples/`, and these spec lines only: the keyword list and the `old`/`result` lines of `grammar.md` with a "Session 6, step 27" note; the string-literal production of `grammar.md` for the escape; `04-syntax.md`'s line 147 sentence gains "and a `never` cannot see the copy between the assignments"; the `fold_lines` row of `09-stdlib.md` and `PRELUDE.md`. Branch `session-05`, one commit per part, `Step 27 part X` in the subject, push after every commit, `zig build test` green at every commit.

## Part A: the file law goes

`MO0302` retired: the check removed, the catalog row marked retired as earlier retired rows are (or removed, whichever the catalog does), the `rejects/` file for it removed, `errors.md` regenerated, `zig build errors`. The function, parameter, nesting, and state-field laws untouched, their rejects files still refused.

## Part B: `state`, `result`, and `old` as names

The lexer keeps the three as keywords only where the grammar reserves them, or the parser accepts them as names in every other position; the worker chooses and says which in the report. Reserved: `state` opening a process's state block and as the bare process state inside `update`, `invariant`, and a process's own functions; `old(` inside `ensures` and `invariant`; `result` inside `ensures`. Everywhere else, a parameter, a binding, a `var`, a field, a `for` or comprehension name, a pattern binding, and a message or variant field take them. Step 26's keyword sentence is kept only for the reserved positions (a bare `state = 1` inside an `update` still says what it says). Corpus: `types/keyword-fields.mo` extended with `state` and `result` as parameters and bindings in a plain function and `old` as a `for` name; `rejects/var-state.mo` and `rejects/old-parameter.mo` become the reserved cases or go, `rejects/state-binding.mo` moves its binding inside an `update`; a `rejects/` file for `result` outside `ensures` if it is still refused. jobq, agent, and any corpus file that renamed around these words may keep their names.

## Part C: a `never` reads values at rest

The runtime (both) records a value for `T.all` when it rests: a binding, a field write's whole struct once the statement ends and the next statement is not an assignment to the same `var`, a return, a message, an assertion; not the `var` between two field assignments of one body. The simplest rule the worker finds that makes the round 6 reproduction pass and keeps every `never` in the corpus tripping where it trips today, said in the report. Corpus: `contracts/never-var-copy.mo` with the round 6 `Pair` reproduction as a passing test plus a `never` that still trips when the pair is returned unequal; `contracts/never-trips.mo` still trips.

## Part D: the small items

1. A `\u{XXXX}` escape in a string literal (1 to 6 hex digits, a Unicode scalar value), and `MO0101` at any other backslash escape the lexer does not know, saying which escapes exist. `basics/strings.mo` gains one of each kind; a `rejects/` file for `"\q"`.
2. `result` as a name outside `ensures` no longer needs a sentence after part B; if it stays refused anywhere, the sentence step 26 gave `state` and `old`.
3. `Fs.fold_lines` at a line that is not UTF-8: the plainest shape that lets a caller count the line and keep folding, chosen by the worker (a `NotText` that carries the fold so far and the line's index, or the line handed to the function as bytes-replaced text with a flag), said in the report, with the `09-stdlib.md` and `PRELUDE.md` rows.

## Part E: both runtimes and the corpus

Every changed corpus file under `mo test`, `--sim 100`, and as a `--tests` binary; `mo fmt --check` clean; the whole suite green.

## Numbers

`lex`, `parse`, `check` bench rows before and after; the count of corpus files and of functions over 70 lines (expected 0); `logstat-4k` and `kv-10k-get` rows under both runtimes before and after part C, since recording changes.

## Done when

Green at every commit; `MO0302` gone; the three words as names with their corpus files; the `never` rule with its file and both runtimes; the escape, the diagnostic, and `fold_lines`; the numbers; pushed; a numbered list "Decisions the brief did not cover".

## Result

Accepted 14 Sep 2026, 16:50 UTC. Five commits in 48 minutes, green at each, 185 of 185. Part A: `MO0302` and its plumbing gone, the other shape laws untouched. Part B: the lexer keeps the three tokens and the parser retags them as names outside the reserved positions; the keyword sentence stays for those positions and `result` gets its own; `keyword-fields.mo` extended, three rejects files moved to the reserved cases, `rejects/unbound-result.mo` new. Part C: a field write skips the `T.all` record when the next statement of the body assigns the same root name; both backends; `contracts/never-var-copy.mo` holds round 6's `Pair` reproduction passing beside a half-moved copy that still trips. Part D: `\u{X}` in both backends, `MO0101` at an unknown escape naming the escapes, `fold_lines` past a non-UTF-8 line with U+FFFD; `basics/strings.mo`, `rejects/unknown-escape.mo`, `programs/not-text.mo` updated. Part E: bench rows. Numbers (best of 20): lex 7,091 → 6,816 µs, parse 17,524 → 17,038, check 61,367 → 59,202 over 151 → 154 files; logstat-4k 103.9 → 105.5 ms interpreted, 13.7 → 13.9 native; kv-10k-get within noise; no function over 70 lines (longest 48).

Fable's probes: a 606-line file accepted; `state` and `result` as parameters and bindings and `old` as an anonymous function's parameter in a plain function, under `mo test` and as a test binary; `state` as a process parameter refused with the sentence; the `Pair` reproduction passing and the half-moved copy tripping in both runtimes; `"\u{85}"` two bytes, `"\u{1F600}"` four, `"\q"` refused; `fold_lines` counting one non-UTF-8 line of three from `mo run` and the binary. Found on the side: a wrong duration unit (`1.second`) crashes at run time with "second is a field of a type tier 2 cannot see" instead of a check-time diagnostic naming the units; to housekeeping.

## Related
- [[control-run-6]]
- [[interpreter-step-25]]
- [[interpreter-step-26]]
- [[decision-log]]
