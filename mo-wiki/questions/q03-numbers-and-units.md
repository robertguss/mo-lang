---
title: "Q3: Numbers and units"
created: 2026-09-12
updated: 2026-09-12
type: question
tags: [syntax, types]
sources: [raw/notion/open-questions-2026-09-12.md]
number: 3
status: answered
answer: in
asked: 2026-09-12
---

# Q3: Numbers and units

**Options:** plain numerals only / numerals with unit suffixes as methods (`200.ms`, `90.days`) / a full units system.
**Recommendation:** unit suffixes as plain functions via dot-call sugar (`200.ms` is `ms(200)` returning a `Duration`), digit separators with `_` (`10_000`), and no implicit numeric conversion anywhere.
**Why:** `within: 200.ms` reads as English, and it's not magic, it's the dot-call sugar we already have. Money should never be a bare number; `5_00` in the examples was a placeholder and should become `Money.cents(500)` or a `Money` literal decided with the standard library.
✅ **Robert: IN** (session 2). Units are ordinary functions reachable by dot-call, so any project can add its own. No literal type suffixes (no 1u64, no 3.14f32); literals are typed by inference at the binding. A full dimensional-analysis units system was considered and rejected as too big for the target domain.

## Related
- [[p15-methods-traits-generics]]
- [[q04-integer-types-and-overflow]]
