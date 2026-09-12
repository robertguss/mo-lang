---
title: "Syntax pick 3: Bindings"
created: 2026-09-12
updated: 2026-09-12
type: syntax-pick
tags: [syntax, state]
sources: [raw/notion/design-journal-2026-09-12.md]
number: 3
status: liked
chosen_by: Robert
---

# Syntax pick 3: Bindings

bare `now = clock.now` is an immutable binding, bound exactly once per scope; rebinding is a compile error; `var` is the only way to get a changing name. Unused-binding error catches typos.

## Related
- [[d13-local-var-and-inout]]
- [[base-example]]
