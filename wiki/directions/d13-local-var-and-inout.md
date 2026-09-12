---
title: "Direction 13: Local `var` with mutable value semantics, plus `inout` parameters"
created: 2026-09-12
updated: 2026-09-12
type: direction
tags: [state, syntax]
sources: [raw/notion/design-journal-2026-09-12.md]
number: 13
status: liked
origin: "Robert"
---

# Direction 13: Local `var` with mutable value semantics, plus `inout` parameters

In. A `var` can never be aliased, never escapes its function, and is semantically just rebinding that reaches inside a value. (Robert, after Claude's unpacking)

## Related
- [[state-model]]
- [[d10-immutable-by-default]]
- [[p03-bindings]]
