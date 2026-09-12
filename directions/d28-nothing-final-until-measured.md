---
title: "Direction 28: Nothing is final until it is measured"
created: 2026-09-12
updated: 2026-09-12
type: direction
tags: [performance, meta]
sources: [raw/notion/design-journal-2026-09-12.md]
number: 28
status: liked
origin: "Robert"
---

# Direction 28: Nothing is final until it is measured

(Robert, session 2) Every decision here — especially the performance-shaped ones — stands only until a benchmark, eval, or test says otherwise. Compile-time performance is of paramount importance, and runtime speed close behind, but both are *measurable*, so neither is settled by argument. Consequences: the project carries a benchmark suite and an eval suite from early on; every performance claim in this journal is a hypothesis with a named way to check it; a decision that measurement contradicts gets reopened without ceremony. This applies to the overflow-check cost, the interpreter-vs-native split, the incremental-rebuild targets, the C-via-Zig backend choice, and any law number.

## Related
- [[d23-compile-speed-first-class]]
- [[q12-law-numbers]]
- [[q04-integer-types-and-overflow]]
