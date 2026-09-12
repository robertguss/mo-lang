---
title: "Q6: The `verified by` line"
created: 2026-09-12
updated: 2026-09-12
type: question
tags: [verification]
sources: [raw/notion/open-questions-2026-09-12.md]
number: 6
status: answered
answer: in
asked: 2026-09-12
---

# Q6: The `verified by` line

**Options:** written by the agent as a claim / computed by the compiler and displayed / both.
**Recommendation:** computed by the compiler, never written by hand. The toolchain appends and maintains a line per module: `verified: contracts, tests, simulation(1_000 runs), proofs(3 of 5)`. Editing it by hand is a compile error.
**Why:** It exists so a human can see the honest verification level at a glance. A human-writable claim is a comment; a compiler-maintained one is a fact.
✅ **Robert: IN** (session 2). In-file at the bottom (not a sidecar) so it travels with the code and shows on a phone. Fixed vocabulary: `contracts`, `tests`, `simulation(N runs)`, `proofs(k of n)`; `types` is implied. A pub module's line is part of its published interface. `proofs(k of n)` deliberately partial so a human can watch it climb.

## Related
- [[d03-source-carries-its-evidence]]
- [[q08-verification-tiers]]
