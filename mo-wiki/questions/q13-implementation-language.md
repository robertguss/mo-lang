---
title: "Q13: Implementation language for the Mo toolchain"
created: 2026-09-12
updated: 2026-09-17
type: question
tags: [compiler, tooling]
sources: [raw/notion/open-questions-2026-09-12.md]
contradictions: [plang-decision-matrix, plang-mo-synthesis, plang-implementation-menu, plang-design-camps, plang-landscape-2026]  # the 13 Sep research syntheses describe a hypothetical Mo this page decided against
number: 13
status: answered
answer: in
asked: 2026-09-12
---

# Q13: Implementation language for the Mo toolchain

**Options:** Zig / Rust / OCaml / Go.
**Recommendation:** **Zig.**
**Why:** Roc moved its compiler from Rust to Zig and got 100x faster incremental builds. TigerBeetle is Zig, so the culture we're borrowing has its tooling there. Zig's toolchain is also our C compiler and cross-compiler, so the whole build has exactly one dependency. OCaml would be faster to write a compiler in but adds a second toolchain. Rust's compile times are the thing we're escaping. Self-hosting Mo in Mo is a later milestone, not a starting point.

## Answer

✅ **Robert: IN** (session 2). Zig.

## Session 3 note (tension 7: the stated reason)

Robert (session 3): "I want you to decide 3 through 7 because we need an answer and then we need to test everything, so your decisions are as good as mine." So this is Claude's call, provisional, and marked with what tests it. **Decision:** Zig stands. The *why* is corrected: Roc's 35ms incremental rebuild needs a Zig nightly on x86-64; on stable Zig at parity Roc measured 8.6s against Rust's 3.4s ([[roc]]). The reasons that hold: one toolchain that is also the C cross-compiler, TigerBeetle culture, no second dependency. Steal Roc's pointer-free index-based compiler data with a memcpy-speed disk cache from day one. **First tested by:** the Mo interpreter's own incremental build time, tracked from the first commit.

## Related
- [[d24-compile-to-c-via-zig]]
- [[d23-compile-speed-first-class]]
