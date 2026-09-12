---
title: "Syntax pick 9: Module header and `never`"
created: 2026-09-12
updated: 2026-09-12
type: syntax-pick
tags: [syntax, negative-space]
sources: [raw/notion/design-journal-2026-09-12.md]
number: 9
status: liked
chosen_by: Robert
---

# Syntax pick 9: Module header and `never`

`module Payments.Refund` with dot paths (Robert's pick; `::` rejected, one symbol one idea, Elixir made the same call). One module per file. `intent "..."` line. A `never` is a quoted sentence plus a block that evaluates true when the bad thing has happened; both mandatory, so a `never` is never just a comment. The sentence is the human's, the block is the agent's. `flows(CardNumber, into: Log)` expresses information-flow rules checkable statically via capabilities.

## Related
- [[d19-negative-space-is-the-contract]]
- [[p14-modules]]
