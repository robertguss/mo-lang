---
title: "Interpreter step 1: lexer and parser, brief for the worker"
created: 2026-09-12
updated: 2026-09-12
type: plan
tags: [compiler, roadmap]
sources: [spec/grammar.md, spec/design-v0/07-toolchain.md]
status: in-progress
---

# Interpreter step 1: lexer and parser, brief for the worker

Roadmap step 5 begins. The worker (Opus) builds `toolchain/src/lexer.zig` and `toolchain/src/parser.zig` so that every file in `examples/` parses, and first brings `examples/` up to date with the Session 5 decisions at the foot of `spec/grammar.md`. Claude (Fable) reviews; Robert watches the numbers.

## Orientation

1. `toolchain/README.md`, then every file in `toolchain/src/` (they are short stubs with the design in doc comments).
2. `mo-wiki/spec/grammar.md` top to bottom, including the Session 5 decisions at the foot. The grammar is the authority; chapter 4 (`spec/design-v0/04-syntax.md`) is the worked example.
3. `examples/README.md` and `examples/GAPS.md`.

## Write scope

`toolchain/` and `examples/` only. Never `mo-wiki/`. Branch `session-05`; `git pull --rebase --autostash` before every push; commit after each part below.

## Part A: the corpus catches up with the decisions

Go through `examples/GAPS.md` line by line. For every gap the Session 5 decisions settle, update the files that used a different default (for example `clock.now(within: 10.ms)` becomes `clock.now`; `use Mo.Sim` lines go; supervisors gain parameters where a child needs capabilities; `reduce` order; `Self` in traits). Delete each settled line from `GAPS.md`; leave the unsettled ones. Keep every file within the corpus rules in `mo-wiki/plans/corpus.md`.

## Part B: lexer

`lexer.zig` implements grammar §1 over `token.zig`: identifiers with a trailing `?`, CapCase names, ints with `_`, floats, strings with `#{...}` holes left whole (the parser splits them), `"""` blocks, atoms, every operator, `#` comments, newlines as tokens, lines joined inside open parens or brackets. Errors are `diag.Record`s with a stable code (`MO0001` unexpected character, `MO0002` unterminated string), never a panic. Unit tests in the file: every keyword, every operator, a string with a hole, a joined line.

## Part C: parser

`parser.zig` is recursive descent, one function per production, building `ast.Tree` as flat index arrays (no pointers; `extra` for wide nodes). Grow `ast.Node.Kind` to one kind per production. Every parse error is a `diag.Record` (`MO01xx`) with the byte offset and what was expected. No recovery needed in step 1: the first error stops the file.

## Part D: the corpus test tightens

Add `pub const implemented: Stage = .parse;` to `pipeline.zig`. `corpus.zig` runs every file to `implemented` and fails the test on any `NotImplemented`, so a stage that is claimed must handle the whole corpus; stages beyond `implemented` still count as skipped. All 50 files, `rejects/` included, must parse (those fail later, at checking). `mo check file.mo` prints parse diagnostics as prose.

## Part E: numbers

`zig build bench -- ../examples 20 --record` and `bench/rebuild.sh --record`. Put the lex and parse rows in the commit message.

## Done when

`zig build test` is green with `implemented = .parse`, all 50 corpus files parse, the bench has recorded rows, and everything is pushed. Then stop; do not start the checker.

## Related
- [[corpus]]
- [[model-bakeoff]]
- [[roadmap]]
- [[q13-implementation-language]]
