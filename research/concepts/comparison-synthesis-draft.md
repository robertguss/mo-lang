---
title: "Comparison synthesis (draft)"
created: 2026-09-12
updated: 2026-09-12
type: concept
tags: [research, meta]
sources: [research/comparisons/elixir.md, research/comparisons/go.md, research/comparisons/rust.md, research/comparisons/roc.md, research/comparisons/koka.md, research/comparisons/austral.md, research/comparisons/hylo.md, research/comparisons/unison.md, research/comparisons/moonbit.md, research/comparisons/bosque.md, research/comparisons/spark-ada-and-dafny.md, research/comparisons/agent-native-cluster.md, research/comparisons/verse.md]
confidence: medium
---

# Comparison synthesis (draft)

A **draft for Fable to finish**, written by the worker session at the end of the comparison pass ([[comparison-pass]]). Nothing here is decided. Robert's rule: these pages *inform* the v0 design doc, and nothing changes a direction until he says so. Evidence and citations live on the thirteen pages linked below. This page only collects.

## Contradictions and tensions (⚠️)

Ordered by how much of Mo each one touches (the worker's judgment).

1. **[[d15-effects-via-capabilities|Direction 15]]'s "the signature is the purity proof" vs closure capture** ([[koka]]). An anonymous function can capture a capability, so a function with no capability parameters can still do I/O through a closure argument. The same hole would let a "no capabilities" package act through callbacks (Q17). Options:
   - (a) second-class capabilities. This conflicts with narrowing (`fs.scoped(...)`, [[p13-capabilities-and-logging|pick 13]]).
   - (b) function types that record captured capabilities.
   - (c) lambdas can't be stored or returned and capture read-only. [[bosque]] ships this rule.
2. **[[p11-loops-and-anonymous-functions|Pick 11]] (bounded `for`) vs [[q08-verification-tiers|Q8]] tier 3 proving `requires`/`ensures`/`never`** ([[bosque]]). Loops need invariants. Partial answer from [[spark-ada-and-dafny]]: LLMs plus solver counterexamples solve benchmark invariants (133/133, 99.5%), but no real-program evidence yet.
3. **[[q04-integer-types-and-overflow|Q4]] (sized integers only) vs [[d22-rust-plus-refinements-types|direction 22]]'s Dafny-level (~82%) expectation** ([[spark-ada-and-dafny]]). Vericoding blames part of Verus's 44% on machine-integer obligations. One option: unbounded integers inside contracts only.
4. **[[q08-verification-tiers|Q8]] (SMT prover in tier 3) vs [[d24-compile-to-c-via-zig|direction 24]] / [[q11-platform-and-stdlib|Q11]] (Zig as the only dependency, zero third-party deps)** ([[austral]], [[bosque]]). Z3 is about 300K lines of C++. Mo must write a solver, vendor one, or relax the rule.
5. **[[q07-process-api|Q7]] ("`send` never blocks or fails") vs [[d04-style-rules-become-laws|direction 4]] (bounded everything)** ([[go]]). "Never blocks or fails" implies an unbounded mailbox. A bound means `send` blocks or returns rain.
6. **[[q01-comments|Q1]] (no doc-comment variant) vs tested doc examples** ([[elixir]]). Weak: `test` blocks may already cover it.
7. **[[q13-implementation-language|Q13]]'s stated reason** ([[roc]]). The "100x faster incremental builds" figure is not yet available on stable Zig. The decision's other reasons stand. This is a correction to the *why*, not the decision.

## Gaps several pages hit (not contradictions)

- **Trait coherence** is undefined ([[rust]], [[roc]], [[hylo]]). Hylo's rule is a ready answer.
- **Crash semantics** are underspecified ([[elixir]], [[austral]], [[koka]], [[verse]]): supervisor strategy, escalation, what a crashed process leaks, and whether a restart starts fresh or keeps state.
- **What tier 3 *is*** ([[elixir]], [[bosque]], [[spark-ada-and-dafny]]): counterexample search or proof, whether "unknown" counts as red, and how to stop agents from gaming it.

## Top ten steals

The worker's ranking, by leverage on the v0 design.

1. **`update` as a transaction.** On a crash, discard that message's state writes and its buffered outgoing effects. Freeze `clock.now` per `update`. The runtime reclaims the process's memory and handles, possibly as a per-process heap region. From [[verse]], [[austral]] and [[koka]], for [[d14-processes-are-the-only-identity|direction 14]] and [[d18-two-kinds-of-failure|direction 18]].
2. **Define tier 3 precisely.** Counterexample search over a decidable fragment; "unknown" isn't red; loop invariants come from a generate-and-check loop with the solver; a change that edits a spec while its proof fails is rejected. From [[bosque]], [[elixir]] and [[spark-ada-and-dafny]], for [[q08-verification-tiers|Q8]].
3. **An honest `verified:` line.** A per-obligation record whose headline is the weakest obligation, plus a Silver-style entry, "no runtime errors proven (k of n)". From [[agent-native-cluster]] (Thermite) and [[spark-ada-and-dafny]], for [[q06-verified-line|Q6]].
4. **Hylo's coherence rule.** One `impl` per type/trait pair; a `pub` impl only in the type's or the trait's module. From [[hylo]], for [[p15-methods-traits-generics|pick 15]].
5. **Content hash and caches.** Unison's hash recipe (names normalized, dependency hashes substituted) per declaration, and a typecheck/test/proof cache that is never invalidated. Proofs are keyed by callee *contract* hashes. From [[unison]], [[spark-ada-and-dafny]] and [[roc]], for [[q10-semantic-ids-and-editing|Q10]] and [[p12-tests|pick 12]].
6. **The agent interface is the toolchain.** An MCP server over edit-by-ID, diagnostics and history, plus version-pinned guidance served by `mo`. No Mo-specific agent. From [[unison]], [[agent-native-cluster]] and [[moonbit]], for [[q09-compiler-diagnostics|Q9]] and [[q10-semantic-ids-and-editing|Q10]].
7. **`mo fix` from day one.** Every language change ships with a rewriter, and every published package version carries an old-hash → new-hash patch. From [[go]] and [[unison]].
8. **Diagnostics that teach.** Caller/callee blame, both conflicting sites, "overlapping `inout` access", a no-false-positives bar, and tier-3 counterexamples delivered as structured fixes rather than raw prover output. From [[agent-native-cluster]], [[rust]], [[hylo]], [[elixir]] and [[spark-ada-and-dafny]].
9. **An eval suite shaped like the real job.** SWE-AGI-style tasks (fixed `pub` API with contracts, hidden tests), whole-program tasks, false-positive rate, p50/p95 time to diagnostics after a one-declaration edit, and p99 latency. From [[moonbit]], [[rust]], [[elixir]] and [[bosque]], for [[d28-nothing-final-until-measured|direction 28]].
10. **Determinism laws for replay.** Stable sort and defined map order in the stdlib; virtual time in `Mo.Sim` advances only when every process is blocked; one clock value per `update`. From [[bosque]], [[go]] and [[verse]], for [[d21-autonomous-crash-fixing|direction 21]].

**Runners-up:**
- a platform manifest in Roc's five parts ([[roc]])
- a spec-altitude *shape diff* ([[moonbit]])
- `Platform` never leaves `main` ([[austral]])
- a `fip`-style "allocates nothing" check ([[koka]])
- `Task.run` bound to its scope, with `race` cancellation for deadlines ([[hylo]], [[verse]])

**Q17 inputs, not recommendations:**
- locked builds, a transparency log, no code execution at fetch or build ([[go]])
- a lockfile audit of platform native code ([[austral]])
- launch-time capability grants ([[agent-native-cluster]])
- the BoltDB lesson: review the hashed bytes, not the VCS view ([[go]])

## Open questions for Robert

Collected from the pages, for Fable to order and ask **one at a time**.

**Types and syntax**
- Supervisor `strategy:` field, and escalation when `max_restarts` is exceeded ([[elixir]])
- Flow narrowing into refinement types inside `if`/`case` ([[elixir]])
- Restrict `try` to the head of a binding or statement ([[go]])
- Named traits vs Roc's per-method `where`; coherence rule ([[rust]], [[roc]], [[hylo]])
- Mark mutation at the call site: nothing, `&v`, or `inout v` ([[hylo]])
- Nested place paths as the only projection ([[hylo]])
- Recursion: ban, bound, or allow ([[koka]])
- A linear `resource` kind for must-consume values ([[austral]])
- Copyable capabilities, or not ([[austral]])
- A spec-only contract kind for `never` clauses too costly to run ([[bosque]])
- Keep tests and `ensures` untouched when an agent changes a body ([[spark-ada-and-dafny]])

**Runtime and tooling**
- After a crash: restart from `init`, or resume from the last committed state with the poison message set aside ([[verse]])
- Hot reload in development only, via the interpreter ([[roc]])
- Ship an agent, or tools only; recommendation: tools only ([[moonbit]])
- A compatibility promise at v1, with a per-module language version ([[go]])
- `forbid reaches(A, B)` as the general form of `flows(...)` ([[agent-native-cluster]])

**Packages (Q17)**
- Two versions of one package in a program? ([[unison]])
- Launch-time capability grants on top of in-code narrowing? ([[agent-native-cluster]])

**Plus a decision on each ⚠️ above.**

## Cross-cutting observations

- **Mo's verification design is now the consensus of the agent-native verification camp:** mandatory contracts, a solver, runtime fallback ([[agent-native-cluster]]). Differentiation has to come from spec-altitude readability, processes with supervision and replay, capabilities as package permissions, and the laws.
- **[[d18-two-kinds-of-failure|Direction 18]] got independent support.** Verse makes runtime errors uncatchable and separate from failure ([[verse]]). MoonBit hit bugs from a catchable cancellation error ([[moonbit]]). Austral agrees on crashing but crashes the whole program ([[austral]]).
- **Zero-shot code in a new language is near 0% on hard tasks, yet agents with a toolchain loop build real systems** ([[moonbit]]). Raw verifier errors teach models poorly ([[spark-ada-and-dafny]]). [[q09-compiler-diagnostics|Q9]] carries the premise.
- **Perceus-style native compilers ship** (Koka, MoonBit, Roc), so [[d10-immutable-by-default|direction 10]]'s memory bet has precedent ([[koka]], [[moonbit]], [[roc]]).
- **Two claims need a primary-source check** before the design doc: MoonBit's reported built-in verification ([[moonbit]]), and Q13's rationale ([[roc]]).

## Notes for Fable

- All 13 pages are `confidence: medium`. The agent-native cluster page uses short per-language entries instead of the idea template, as the brief allowed.
- The shared ledger `research/comparisons/.ledger.json` holds 124 sources, and ids were never renumbered. A few are uncited: fetches that returned junk were deleted before commit, including [36], [37] and [115]. Where a fetch cut off before a cited section, a `-part2` or section excerpt was saved to `raw/`.
- Two pages were edited after they were first committed:
  - Roc: its effect-polymorphism line now points to the closure gap on Koka.
  - MoonBit: the IEEE TSE acceptance is marked as a secondary-source claim.
- No page under `directions/`, `questions/` or `syntax/` was changed.

## Related
- [[comparison-pass]]
- [[language-landscape]]
- [[steal-list]]
- [[roadmap]]
