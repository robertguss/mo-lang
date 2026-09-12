---
title: "Q8: The verification dial in practice"
created: 2026-09-12
updated: 2026-09-12
type: question
tags: [verification, performance]
sources: [raw/notion/open-questions-2026-09-12.md]
number: 8
status: answered
answer: in
asked: 2026-09-12
---

# Q8: The verification dial in practice

**Question:** what checks run when, and what does an agent wait for?
**Recommendation:** three tiers, always in this order.
1. **Instant, blocking:** types, exhaustiveness, capabilities, `flows`, contract *presence*, test *presence*. The compile loop. Target under 50ms incremental.
2. **Fast, blocking:** contracts and invariants checked at runtime while running the module's own tests and `rejects` tests. Target under 100ms per changed function.
3. **Slow, background, cached by hash:** property tests under many seeds, simulation with fault injection, and the SMT prover trying to discharge `requires`/`ensures`/`never` statically. Results upgrade the `verified:` line when they land. An agent never waits on tier 3 to see whether its code compiles, but a merge into a supervised deployment requires tier 3 green.
**Why:** It keeps the agent loop fast ([[d23-compile-speed-first-class|direction 23]]) without lowering the bar. The Dafny numbers say off-the-shelf models discharge contract-style proofs 82% of the time, so tier 3 will succeed often and quietly.
✅ **Robert: IN** (session 2). Also settled: a tier-3 failure on merged code is a bug, not a flag — a failed property is a found counterexample with seed + log, so the agent takes it as a fix task with no human involved ([[d21-autonomous-crash-fixing|direction 21]]); a human is pulled in only if the fix changes a `never`. The 50ms / 100ms numbers are hypotheses that go into the benchmark suite on day one ([[d28-nothing-final-until-measured|direction 28]]).

## Session 3 note (tension 2: loops vs tier 3)

Loops need invariants to prove `ensures`, and no general technique exists ([[bosque]]). Robert: **in** on keeping `for` with no invariant syntax. Tier 3 first tries small-model checking (bounded unrolling, counterexample search) and simple invariant inference; when that fails the function's `verified:` line says "tested, not proven" ([[q06-verified-line|Q6]]). An `invariant` line inside loops is a later add-on only if measurement ([[d28-nothing-final-until-measured|direction 28]]) shows agents need it. Evidence so far ([[spark-ada-and-dafny]]) is benchmark-sized only.

## Session 3 note (tension 4: SMT prover vs zero-dependency toolchain)

Robert (session 3): "I want you to decide 3 through 7 because we need an answer and then we need to test everything, so your decisions are as good as mine." So this is Claude's call, provisional, and marked with what tests it. **Decision:** tier 3 in v0 is property testing under many seeds plus simulation with fault injection, all run by the interpreter, zero dependencies. Static proving is a separate optional binary, `mo prove`, which vendors a pinned, hashed, statically linked solver and is never in the build path of a user program. "Zig as the only dependency" ([[d24-compile-to-c-via-zig|direction 24]], [[q11-platform-and-stdlib|Q11]]) applies to building Mo programs and the core toolchain, not to the background prover. Bosque-style small-model checking written in Zig may later cover enough that `mo prove` stays rare. → [[d32-proving-is-a-separate-tool|direction 32]]. **First tested by:** how far the interpreter's property tests get on the corpus before anyone misses a prover.

## Related
- [[d23-compile-speed-first-class]]
- [[q06-verified-line]]
- [[d21-autonomous-crash-fixing]]
- [[p12-tests]]
