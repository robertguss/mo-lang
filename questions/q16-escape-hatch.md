---
title: "Q16: Escape hatch, revisited"
created: 2026-09-12
updated: 2026-09-12
type: question
tags: [laws, effects]
sources: [raw/notion/open-questions-2026-09-12.md]
number: 16
status: answered
answer: in
asked: 2026-09-12
---

# Q16: Escape hatch, revisited

**Question:** parked in session 1: laws with no override, ever?
**Recommendation:** **yes, no override in the language**, and the platform is the escape hatch. If a program genuinely needs something the laws forbid, that thing gets written once in a platform, audited, and exposed as a capability.
**Why:** With the platform split ([[q11-platform-and-stdlib|Q11]]) this is no longer a hard stance, it's a place. Every "unsafe" thing has a home, and it's never in application code.

## Answer

✅ **Robert: IN** (session 2). No override in the language; the platform is the escape hatch.

## Related
- [[q11-platform-and-stdlib]]
- [[d04-style-rules-become-laws]]
