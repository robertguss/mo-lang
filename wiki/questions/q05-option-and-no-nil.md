---
title: "Q5: Option and the absence of nil"
created: 2026-09-12
updated: 2026-09-12
type: question
tags: [types, syntax]
sources: [raw/notion/open-questions-2026-09-12.md]
number: 5
status: answered
answer: in
asked: 2026-09-12
---

# Q5: Option and the absence of nil

**Options:** `Option(T)` with `Some`/`None` (Rust) / `Maybe` with `Just`/`Nothing` (Haskell, Elm) / a `T?` shorthand (Swift, Kotlin).
**Recommendation:** `Option(T)` with `Some(x)` and `None`, matched with `case` like any enum, plus one convenience: `value or default` as the only shorthand.
**Why:** `Option` and `Some` are the names models know best. `or` for defaults reads like English and covers 80% of uses; everything else is an explicit `case`. No `?.` chains, no `!!` unwraps, no implicit nil anywhere.
✅ **Robert: IN** (session 2). Same rule as Result: nothing turns a None into a crash. If absence is a bug at that point, the agent writes `requires x is Some(_)` and the contract crashes it honestly. No `if let`, no `T?` shorthand. Accepted cost: more `case` blocks than Swift/Kotlin; the function-length law pushes those into helpers, which is the intended direction.

## Related
- [[p06-results-and-propagation]]
- [[p05-pattern-matching]]
