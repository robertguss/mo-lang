---
title: "Direction 17: Every effectful call carries a mandatory deadline"
created: 2026-09-12
updated: 2026-09-12
type: direction
tags: [effects, errors]
sources: [raw/notion/design-journal-2026-09-12.md]
number: 17
status: liked
origin: "Robert"
---

# Direction 17: Every effectful call carries a mandatory deadline

Bounded waits, extending Power of Ten's bounded loops. Timeout is an ordinary `Err` variant the exhaustiveness checker forces you to handle. (Robert: matches)

## Related
- [[effects-and-capabilities]]
- [[q07-process-api]]
- [[d16-direct-style-io]]
