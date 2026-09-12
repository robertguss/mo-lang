---
title: "Syntax pick 2: Definition line"
created: 2026-09-12
updated: 2026-09-12
type: syntax-pick
tags: [syntax]
sources: [raw/notion/design-journal-2026-09-12.md]
number: 2
status: liked
chosen_by: Robert
---

# Syntax pick 2: Definition line

`fn refund(db: Ledger, clock: Clock) : Result(Refund, RefundError)`. `fn` keyword (not `def`); `name: Type` with no space before the colon (Robert's adjustment); `:` for the return type, not `->`; generics with parens, no angle brackets.

## Related
- [[base-example]]
- [[d11-statically-typed]]
