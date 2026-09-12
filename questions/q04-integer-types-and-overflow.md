---
title: "Q4: Integer types and overflow"
created: 2026-09-12
updated: 2026-09-12
type: question
tags: [types, errors]
sources: [raw/notion/open-questions-2026-09-12.md]
number: 4
status: answered
answer: in
asked: 2026-09-12
---

# Q4: Integer types and overflow

**Options:** wrap silently (C, Go) / crash on overflow (Rust debug, Zig safe modes) / checked types that return `Option`.
**Recommendation:** explicitly sized types only (`UInt8` ... `UInt64`, `Int8` ... `Int64`, `Float64`), overflow is a bug and crashes the process, and `checked_add` style functions return `Option` when the caller wants to handle it.
**Why:** Tiger Style: explicitly sized types. Rain-vs-roof: an unexpected overflow is a broken roof. Silent wrap is the classic hidden bug agents cannot see.
✅ **Robert: IN** (session 2). Crash on overflow in **every** build, not only debug — Rust's debug-only check was rejected because the guarantee must hold in the build that matters. Named variants checked_/saturating_/wrapping_ put the intent in the source. Integer divide-by-zero crashes; Float64 follows IEEE. Accepted cost: a few percent on hot integer loops, to be recovered by contract-proved bound elision and the background SMT tier — and, per the measurement rule, to be verified rather than assumed.

## Related
- [[d18-two-kinds-of-failure]]
- [[d28-nothing-final-until-measured]]
