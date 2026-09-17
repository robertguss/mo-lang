---
title: "Q12: Law numbers"
created: 2026-09-12
updated: 2026-09-17
type: question
tags: [laws]
sources: [raw/notion/open-questions-2026-09-12.md]
number: 12
status: answered
answer: counter
asked: 2026-09-12
---

# Q12: Law numbers

**Question:** the concrete limits behind the laws.
**Recommendation:** function bodies at most **40 lines** (Tiger Style is 70; agents write tighter, and 40 fits a phone screen and a context window chunk). Files at most **500 lines**. Parameters at most **6** (beyond that, a struct). Nesting depth at most **3**. Process state at most **12 fields** before the compiler demands a nested process. All enforced as errors, all tunable per-project downward only, never upward.
**Why:** Numbers make laws real. Every one of these is a forcing function toward decomposition, which is what keeps units agent-sized.
**Session 2 note:** all five numbers are hypotheses under [[d28-nothing-final-until-measured|direction 28]] — the corpus (roadmap step 4) is where we measure whether 40 lines is right.

## Answer

↩ **Robert: COUNTER** (session 2). Adopt Tiger Style's **70 lines** per function, not 40 — 40 is too small, and fitting a phone screen is not a design criterion. Other numbers stand: file ≤ 500, params ≤ 6, nesting ≤ 3, process state ≤ 12 fields; errors not warnings; tighten-only per project. (Since: the file-length law was dropped and MO0302 retired at step 27, and on the review of 14 Sep the counted shape laws became project settings with defaults, chapter 2 and chapter 10 §3; the 70-line function rule is a setting too.) All hypotheses under [[d28-nothing-final-until-measured|direction 28]]. 70 still keeps a declaration to one [[id-addressed-editing|ID edit]].

## Related
- [[tiger-style-and-power-of-ten]]
- [[d28-nothing-final-until-measured]]
- [[d04-style-rules-become-laws]]
