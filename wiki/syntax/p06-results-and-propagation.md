---
title: "Syntax pick 6: Results and propagation"
created: 2026-09-12
updated: 2026-09-12
type: syntax-pick
tags: [syntax, errors]
sources: [raw/notion/design-journal-2026-09-12.md]
number: 6
status: liked
chosen_by: Robert
---

# Syntax pick 6: Results and propagation

predicates end in `?` (`charge.refunded?`); propagation is the `try` prefix (`charge = try db.find_charge(id, within: 200.ms)`), never postfix `?`; constructors are the capitalized variants `Ok(...)` / `Error(...)`; **no unwrap, no expect**, `try` is the only propagation and nothing turns an `Error` into a crash.

## Related
- [[d18-two-kinds-of-failure]]
- [[q05-option-and-no-nil]]
