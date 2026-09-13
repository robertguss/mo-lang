---
title: "Step 5: the formatter, brief for the worker"
created: 2026-09-12
updated: 2026-09-12
type: plan
tags: [tooling, syntax, compiler]
sources: [spec/design-v0/02-laws.md, spec/design-v0/04-syntax.md, spec/grammar.md]
status: done
---

# Step 5: the formatter, brief for the worker

Chapter 2: "Ruby offers five ways to write everything. Mo offers one. Column limits, indent width, blank lines, and ordering are the formatter's job and never a choice." The corpus already has two spacing styles. Step 5 is `mo fmt`, built before program 1 so every Mo file an agent writes from now on has one shape. Plus three small checker items the milestone surfaced.

## Orientation

`toolchain/README.md`, `toolchain/src/ast.zig`, `parser.zig`, `lexer.zig` (comments and blank lines are not in the tree today; the formatter needs them), `spec/design-v0/04-syntax.md` for the shape of every construct, the Session 5 decisions in `spec/grammar.md`.

## Write scope

`toolchain/` and `examples/`, branch `session-05`, `git pull --rebase --autostash` before every push, one commit per part.

## Part A: the rules (`toolchain/FORMAT.md`, then the code)

Write the rules down first, as a table a reader can check a file against, then implement them. The rules, decided:

- Two-space indent, spaces only, no trailing whitespace, one newline at end of file, column limit 100; a line over the limit breaks after a comma inside parens with continuation lines indented one level.
- Blank lines: exactly one after the `expose` line, one before `intent`, one between top-level declarations, one between the contract lines and the body, none at the start or end of a block, never two in a row. Inside a process: `state` block, then a blank line, then `invariant` blocks each followed by a blank line, then the `message` lines together with no blanks, a blank line, then `update`. Inside `state`, `struct`, `enum`: no blank lines.
- Spacing: `arg: Type`, `) : Ret`, one space around binary operators, none inside parens or brackets, none before a comma and one after, `fn(x) x > 0 end` on one line when it fits.
- `case` arms: `Pattern: expr` on one line when the expr fits; otherwise `Pattern:` then the block indented. Arms are never blank-separated.
- Ordering: `module`, `expose`, `use` lines sorted, `intent`, `never` blocks, then declarations in the author's order, then `test`, `property` in the author's order at the bottom, then `verified:`. The `expose` list keeps the author's order (it is a table of contents).
- Comments: a `#` line stays attached to the line below it; a trailing `#` comment stays on its line after two spaces. The formatter never moves or drops a comment.
- Strings and numbers are never changed.

## Part B: `mo fmt`

`mo fmt <file>` rewrites in place; `mo fmt --check <file>` exits 1 with a unified diff and changes nothing; `mo fmt --stdout`. The formatter parses, then prints from the tree plus the preserved comments and blank-line intent; it must not touch a file that fails to parse. Property: formatting is idempotent, and parsing the output gives a tree equal to parsing the input (add both as Zig tests over the whole corpus).

## Part C: the loop rule as a diagnostic

Chapter 4's rule "a pure body is written with map, filter, or reduce; for is for effects, try, break, or return" is enforced by `mo fmt --check` and `mo check` as `MO0501` ("this for has a pure body; write it as map, filter, or reduce"), not rewritten. Rewriting is `mo fix`, later. A body is pure when it contains no capability call, no `try`, no `break`, no `return`, and no assignment to a name declared outside the loop.

## Part D: three checker items

- `for _ in 0..n` is allowed: `_` as the loop binder means the index is unused, and the unused-binding law does not fire. Grammar change: `for = "for" (ident | "_") "in" expr NL block "end" NL`; note it in the code, Fable updates the grammar.
- A `state` field whose type has no zero value and no `= expr` is a compile error `MO0319` at check time, not a crash at start.
- Confirm `MO0308` on an integer or string scrutinee says "does not cover every UInt32; add a `_` arm" (step 3 asked for it; verify and fix if not).

## Part E: the corpus is formatted

Run `mo fmt` over every file in `examples/`, commit the result as its own commit so the diff shows exactly what the rules changed, and add `mo fmt --check` over the corpus to the corpus test.

## Part F: numbers

Add a `fmt` row to the bench (format the whole corpus to memory). `zig build bench -- ../examples 20 --record`, `bench/rebuild.sh --record`.

## Done when

`zig build test` green with the idempotence and round-trip tests, the corpus formatted and passing `--check`, the three checker items in, bench rows recorded, pushed. Then list, in the final message only, every decision the brief did not cover.

## Related
- [[interpreter-step-4]]
- [[p11-loops-and-anonymous-functions]]
- [[decision-log]]
