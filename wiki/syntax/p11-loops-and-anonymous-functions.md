---
title: "Syntax pick 11: Loops and anonymous functions"
created: 2026-09-12
updated: 2026-09-12
type: syntax-pick
tags: [syntax]
sources: [raw/notion/design-journal-2026-09-12.md]
number: 11
status: liked
chosen_by: Robert
---

# Syntax pick 11: Loops and anonymous functions

`for x in xs ... end` and `for i in 0..n ... end` are the only loops, bounded by construction; no `while`, no `loop`; `break` allowed within a bounded loop. Anonymous functions reuse the keyword: `fn(r) r.charge == c.id end`, Elixir-style. Ruby trailing `do |x|` blocks rejected as a second way.

## Session 3 note (tension 1)

Robert: **in** on restricting anonymous functions to call arguments. `pred = fn(c) ... end` and returning an anonymous `fn` are compile errors; captures are read-only. Named functions remain first-class values (`handlers = [on_refund]`). See [[d31-effects-never-hide-in-a-value|direction 31]].

## Session 3 note (tension 2)

Robert: **in** on keeping bounded `for` loops as they are; no `invariant` syntax for now. Unproven loops are reported honestly by the `verified:` line, never blocked. See [[q08-verification-tiers|Q8]].

## Related
- [[tiger-style-and-power-of-ten]]
- [[base-example]]
