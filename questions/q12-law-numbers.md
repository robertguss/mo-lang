---
title: "Q12: Law numbers"
created: 2026-09-12
updated: 2026-09-12
type: question
tags: [laws]
sources: [raw/notion/open-questions-2026-09-12.md]
number: 12
status: pending
answer: pending
asked: 2026-09-12
---

# Q12: Law numbers

**Question:** the concrete limits behind the laws.
**Recommendation:** function bodies at most **40 lines** (Tiger Style is 70; agents write tighter, and 40 fits a phone screen and a context window chunk). Files at most **500 lines**. Parameters at most **6** (beyond that, a struct). Nesting depth at most **3**. Process state at most **12 fields** before the compiler demands a nested process. All enforced as errors, all tunable per-project downward only, never upward.
**Why:** Numbers make laws real. Every one of these is a forcing function toward decomposition, which is what keeps units agent-sized.
**Session 2 note:** all five numbers are hypotheses under [[d28-nothing-final-until-measured|direction 28]] — the corpus (roadmap step 4) is where we measure whether 40 lines is right.
✍️ **Robert (in / no / counter):**

## Related
- [[tiger-style-and-power-of-ten]]
- [[d28-nothing-final-until-measured]]
- [[d04-style-rules-become-laws]]
