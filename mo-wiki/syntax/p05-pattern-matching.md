---
title: "Syntax pick 5: Pattern matching"
created: 2026-09-12
updated: 2026-09-12
type: syntax-pick
tags: [syntax]
sources: [raw/notion/design-journal-2026-09-12.md]
number: 5
status: liked
chosen_by: Robert
---

# Syntax pick 5: Pattern matching

`case value ... end` with arms written `Pattern: expression` (Robert's pick, replacing `->`; `->` is now gone from the language). Multi-line arms run until the next `Pattern:` line or `end`, no per-arm closer, Ruby `when` style. Note: `:` now means both "is a type" and "maps to" by context, a deliberate bend of one-symbol-one-idea since both readings are universal (Ruby, Python, JSON) and never overlap. No `when`. Exhaustive always; no catch-all `_` on closed enums; guards via `if` on an arm; nested destructuring.

## Related
- [[q05-option-and-no-nil]]
- [[base-example]]
