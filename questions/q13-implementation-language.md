---
title: "Q13: Implementation language for the Mo toolchain"
created: 2026-09-12
updated: 2026-09-12
type: question
tags: [compiler, tooling]
sources: [raw/notion/open-questions-2026-09-12.md]
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

## Related
- [[d24-compile-to-c-via-zig]]
- [[d23-compile-speed-first-class]]
