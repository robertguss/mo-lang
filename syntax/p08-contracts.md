---
title: "Syntax pick 8: Contracts"
created: 2026-09-12
updated: 2026-09-12
type: syntax-pick
tags: [syntax, contracts]
sources: [raw/notion/design-journal-2026-09-12.md]
number: 8
status: liked
chosen_by: Robert
---

# Syntax pick 8: Contracts

`requires` / `ensures` lines come directly after the signature line, then a blank line, then the body, all inside the `fn ... end`. Lines above the blank line are spec altitude. `result` names the return value, `old(x)` the entry value, `is` does an inline pattern test (`result is Ok(c) implies c.refunded?`).

## Related
- [[two-altitudes]]
- [[base-example]]
