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

## Session 3 note (tension 3: sized ints vs proof rate)

Robert (session 3): "I want you to decide 3 through 7 because we need an answer and then we need to test everything, so your decisions are as good as mine." So this is Claude's call, provisional, and marked with what tests it. **Decision:** bodies keep sized integers and crash on overflow (this answer stands). Contract expressions (`requires`/`ensures`/`never`) are evaluated in unbounded mathematical integers, so spec arithmetic never overflows. Tier 3 reports two obligations separately: "ensures proven" and "no overflow proven (k of n)". No new syntax. **First tested by:** the tier-2 contract runtime in the interpreter (specs must still run, widening on demand) and later the tier-3 proof rate on the corpus. See [[spark-ada-and-dafny]].

## Related
- [[d18-two-kinds-of-failure]]
- [[d28-nothing-final-until-measured]]
