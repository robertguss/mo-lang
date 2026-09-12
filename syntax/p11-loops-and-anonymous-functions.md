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

## Related
- [[tiger-style-and-power-of-ten]]
- [[base-example]]
