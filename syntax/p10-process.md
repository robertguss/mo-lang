---
title: "Syntax pick 10: Process"
created: 2026-09-12
updated: 2026-09-12
type: syntax-pick
tags: [syntax, processes]
sources: [raw/notion/design-journal-2026-09-12.md]
number: 10
status: liked
chosen_by: Robert
---

# Syntax pick 10: Process

`process Name(db: Ledger, clock: Clock) ... end` with capabilities as process parameters (the process's entire authority on line one). `state ... end` block is the struct in the box. `message Increment` lines, one per message. `fn update(state, message)` is the one function that changes the box; **`state` is implicitly mutable inside `update`** (`state.count += 1`), no return needed. `invariant "sentence" ... end` in the same shape as `never`, checked after every update. Robert found the first version confusing; the counter example clarified it.

## Related
- [[d14-processes-are-the-only-identity]]
- [[q07-process-api]]
