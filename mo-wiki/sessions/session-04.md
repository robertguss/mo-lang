---
title: "Session 4 — 12 Sep 2026"
created: 2026-09-12
updated: 2026-09-12
type: session
tags: [meta, syntax]
sources: [spec/design-v0/04-syntax.md, spec/grammar.md]
date: 2026-09-12
session: 4
---

# Session 4 — 12 Sep 2026

Short session on the VPS; Robert is moving the work to his laptop. Only syntax edits to `spec/design-v0/04-syntax.md` happened.

## What happened

- `pub` is gone. Robert **in** on the Elm-style `expose a, b, C` line under `module`; private by default, no marker on declarations → [[p14-modules|pick 14]], chapters 2–7, `grammar.md`.
- `use A.B{X, Y}` drops the dot before the braces (Robert).
- The comprehension `for` in `never` and `property` had no `end`; Robert: no whitespace sensitivity, everything explicit. Every `for` now closes with `end`.
- Loops vs combinators: Robert asked whether `for` should go the way JS's did. **In** on keeping `for` plus `map`/`filter`/`reduce` with one formatter rule: pure body → combinator, `for` only for effects, `try`, `break`, `return`. Dropping `for` (the Bosque bet) stays open, first tested by the corpus → [[p11-loops-and-anonymous-functions|pick 11]].
- Robert: chapter 4 must always show the current syntax; dated notes below are the changelog only.

## Next

1. Robert's remaining edits to `design-v0/`, one chapter at a time (chapters 1–3 and 5–8 not yet reviewed by him).
2. Roadmap step 4: the corpus in `examples/` (Opus worker), reviewed one by one.
3. Roadmap step 5: the Zig interpreter layout, benchmark harness from day one.

## Related
- [[session-03]]
- [[roadmap]]
