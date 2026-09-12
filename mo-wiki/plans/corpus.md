---
title: "Corpus: brief for the worker session"
created: 2026-09-12
updated: 2026-09-12
type: plan
tags: [roadmap, syntax]
sources: [spec/design-v0/04-syntax.md, spec/grammar.md]
status: in-progress
---

# Corpus: brief for the worker session

Roadmap step 4: `examples/` becomes 30–50 tiny Mo programs that together exercise every construct in `spec/design-v0/04-syntax.md` and every production in `spec/grammar.md`. Written by a worker session (Opus). Robert reviews each one in chat with Claude (Fable). The corpus is the first test of every syntax pick, the first training material for agents, and the first test suite for the interpreter (`spec/design-v0/08-milestone.md`).

## Orientation (do first)

1. Read `mo-wiki/SCHEMA.md` (conventions, Robert's taste), then `mo-wiki/spec/design-v0/` top to bottom (eight short chapters), then `mo-wiki/spec/grammar.md`. Chapter 4 and the grammar are the authority on syntax. Chapters 2 and 3 are the authority on what must and must not compile.
2. Skim `mo-wiki/syntax/` (picks p01–p15) only if a rule in chapter 4 is unclear.

## Write scope

Only `examples/`. Never write to `mo-wiki/`, `toolchain/`, `README.md`, or `HANDOFF.md`. Commit after every five files: `git pull --rebase --autostash && git add examples && git commit -m "Corpus: <group> <n>–<m>" && git push`. Use the commit trailers from the session's system reminder.

## The rules for every file

- One module per file, file path equals module path: `module Basics.Bindings` lives at `examples/basics/bindings.mo`.
- Every file is complete: `module`, `expose`, `intent "..."`, declarations, and at least one `test` at the bottom. No `verified:` line (the toolchain computes it).
- Tiny: 15–40 lines. One construct is the point of the file; everything else in it is the plainest possible code. A reader learns exactly one thing per file.
- Only syntax that is in the grammar. **Never invent syntax.** If a program needs something the grammar and chapter 4 do not define (a stdlib function, a map literal, a way to print), stop, write the plainest zero-new-syntax option you can find inside the grammar, and record the gap in `examples/GAPS.md` (one line per gap: file, what was missing, the default you used). Robert decides on the gaps; the worker does not.
- Stdlib calls: only what chapter 4 already uses (`push`, `filter`, `map`, `reduce`, `size`, `cents`, `zero`, `days`, `ms`, `minute`, `fixture`, `emit`, `scoped`, `read_only`, `now`) plus obvious dot-call names on lists and strings. Anything beyond that goes in `GAPS.md`.
- Every `requires` has a `test rejects` that trips it (law). Every effectful call passes `within:`. Every `case` is exhaustive with no catch-all on a closed enum. Every `for` closes with `end`, and a pure body uses `map`/`filter`/`reduce` instead. Nothing aliases a `var`; anonymous functions appear only as call arguments.
- Comments are `#`, at most one per file, only where the point of the file is not obvious from the intent line.
- Ruby-nice: short names, no ceremony, no clever tricks.

## The programs

Numbers are the reading order for `examples/README.md`, not part of the file name.

**basics/** — `bindings` (1: `x =`, `var`, `+=`), `numbers` (2: sized ints, `10_000`, `checked_add`, `saturating_sub`, `wrapping_mul`, a float), `strings` (3: interpolation, `"""`, `size` in graphemes vs `bytes`), `predicates` (4: `?` functions and dot-call sugar), `tuples` (5: build, `.0`, destructure in `case`), `lists` (6: literal, `push`, `map`, `filter`, `reduce`), `option` (7: `Some`, `None`, `or`, `case`), `result` (8: `Ok`, `Error`, `try` through two calls), `if` (9: statement, expression form, trailing `if` on `return`), `case` (10: guards, nested destructuring, literal arms, `_` inside a pattern), `for` (11: range, list, `break`, why this one is a `for` and not a combinator), `anonymous-functions` (12: one-line and block form as arguments).

**types/** — `struct` (13: named construction, `var copy` update), `enum` (14: data variants and matching), `refinement` (15: `type Money = UInt64 where ...`, a `rejects` test at the boundary), `generics` (16: `fn first(xs: List(T)) : Option(T)` and a `where T: Trait` bound), `trait` (17: `trait` plus `impl`, one function), `nested` (18: `Result(Option(T), E)` handled fully).

**contracts/** — `requires` (19: with its `rejects` test), `ensures` (20: `result`, `old`, `is`, `implies`), `never` (21: two-generator comprehension with a guard), `flows` (22: `flows(CardNumber, into: Events)` beside a struct that carries one).

**effects/** — `clock` (23: a function taking `Clock`, `within:` on the call), `pure-vs-effectful` (24: the same computation with and without a capability parameter), `timeout` (25: `Timeout` as an ordinary error variant handled by the caller), `narrowing` (26: `fs.scoped(...).read_only` passed down), `sim` (27: `use Mo.Sim` and a test that runs against it).

**processes/** — `counter` (28: `state`, two `message` lines, `update`), `ask` (29: a message with a reply type, `ask` with `within:`), `mailbox` (30: `mailbox: N` and the sender-crashes rule stated in the intent), `invariant` (31: `invariant` with `old(state.x)`), `supervisor` (32: `supervisor` with `restart:` and `max_restarts:`), `pipeline` (33: two processes, one sends to the other).

**tests/** — `test` (34: `assert`, `assert x is Ok(c)`), `rejects` (35: one `requires`, one `rejects`), `property` (36: `any(Type)` with a guard).

**recipes/** — `rate-limiter` (37: the recipe from chapter 6, `needs Clock`), `pure-recipe` (38: `needs nothing`).

**rejects/** — programs that must **not** compile, one law each, first line after `intent` a comment `# expect error: <one sentence>`: `rebinding` (39), `unused-binding` (40), `missing-rejects-test` (41), `catch-all-arm` (42), `unconsumed-result` (43), `seven-parameters` (44), `aliased-var` (45), `stored-anonymous-function` (46), `default-parameter` (47), `missing-within` (48), `hand-edited-verified` (49), `unsupervised-process` (50).

**`examples/README.md`** — replace the current placeholder: one line per file in reading order, grouped as above, plus the two rules a reader needs (file path equals module path; `rejects/` must fail to compile).

**Not in the corpus** — `fn main(platform: Platform)` and printing: the grammar does not yet define `main` or an output capability. Leave both out; the corpus is modules plus tests, which is exactly what the interpreter milestone runs.

## Done when

All 50 files, `GAPS.md`, and `README.md` exist, every file follows the rules above, and the last commit is pushed. Then stop; do not review, do not write to the wiki.

## Related
- [[roadmap]]
- [[session-05]]
- [[p11-loops-and-anonymous-functions]]
- [[p14-modules]]
