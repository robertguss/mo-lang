---
title: "Mo vs SPARK Ada and Dafny"
created: 2026-09-12
updated: 2026-09-12
type: comparison
tags: [research, contracts, verification]
sources: [raw/articles/adacore-spark-product.md, raw/articles/spark-ug-usage-scenarios-levels.md, raw/articles/spark-ug-subprogram-contracts.md, raw/articles/spark-ug-gnatprove.md, raw/papers/vericoding-benchmark.md, raw/papers/vericoding-benchmark-part2.md, raw/papers/dafny-as-verification-aware-il.md, raw/papers/marmaragan-llm-spark-annotations.md, raw/papers/marmaragan-llm-spark-annotations-part2.md, raw/papers/dafnybench.md, raw/papers/dafnybench-part2.md, raw/papers/llm-smt-loop-invariants-hybrid.md, raw/papers/neuroinv-loop-invariants.md, raw/articles/autofy-spark-synthesis-tum.md]
confidence: medium
---

# Mo vs SPARK Ada and Dafny

**One line:** the two working precedents for Mo's contracts-plus-prover design ([[d03-source-carries-its-evidence|direction 3]], [[q08-verification-tiers|Q8]]): SPARK for contracts that both run and get proved, Dafny for the contract shapes LLMs discharge best. On the list to find out which contract *shapes* agents handle well and where they fail.

## What it is (status as of Sep 2026)

SPARK is a formally defined subset of Ada for provably correct software.[102] Its contracts "are part of the language, not structured comments": checked by the compiler, proved by the SPARK tools, and given "execution semantics".[105] Qualification support exists for DO-178, ISO 26262 and IEC 61508.[105] Dafny is a verification-aware language that compiles to mainstream targets. One proposal uses it as a hidden intermediate language, so the user never sees Dafny.[101] Research on LLM-written verified code is active in both: Autofy (TU Munich, 2026) has LLMs write SPARK programs that must compile, prove and pass tests,[108] and the vericoding benchmark compares Dafny with Verus and Lean.[100]

## The ideas, one by one

- **One contract, two semantics.** With assertions enabled, "the precondition of a subprogram is checked at run time every time the subprogram is called", and a failure raises an exception.[109] GNATprove "interprets annotations exactly like they are interpreted at run time during tests".[110] Once it proves a check can never fail, the compiler can remove it.[105]
  - *Mo today:* `requires` / `ensures` ([[p08-contracts|pick 8]]). Runtime checks in tier 2, proofs in tier 3 ([[q08-verification-tiers|Q8]]). Refinements are "discharged statically when provable and at runtime otherwise" ([[d22-rust-plus-refinements-types|direction 22]]).
  - *Verdict:* **already have.** SPARK is the industrial precedent for Q8, and for Q4's plan to recover overflow-check cost by proof ([[q04-integer-types-and-overflow|Q4]]).

- **Named assurance levels.** Stone means valid SPARK. Bronze adds initialization and data flow. Silver is "absence of run-time errors". Gold is "proof of key integrity properties". Platinum is full functional proof, "seldom applicable due to the high cost".[104] The guidance sets Silver as "the default target for critical software".[104]
  - *Mo today:* the `verified:` line with `contracts, tests, simulation(N runs), proofs(k of n)` ([[q06-verified-line|Q6]]).
  - *Verdict:* **steal** Silver as its own entry. "No runtime error can occur" (overflow, bounds, divide by zero) is the class Q4 crashes on, and it is provable separately from functional contracts.

- **Modular proof.** SPARK verifies "one subprogram at a time". A callee is assumed to meet its postcondition whenever its precondition holds, which is why it scales to teams.[105]
  - *Mo today:* tier 3 cached by hash ([[q08-verification-tiers|Q8]]). `pub` contracts are part of the interface ([[p14-modules|pick 14]]).
  - *Verdict:* **already have** in spirit. **Steal** the cache key: a proof depends on the declaration's hash plus its callees' *contract* hashes, not their bodies (see [[unison]]).

- **Loop invariants are the weak link, unless a solver talks back.** On vericoding, LLMs "easily generate implementations … but struggle more with proofs — adding invariants/assertions".[100] Marmaragan (GPT-4o) solved 36 of 71 SPARK cases (50.7%) and did better on `Assert` than on loop invariants.[102] On DafnyBench the best model filled in enough hints to verify 68% of 782 programs. About 54% succeeded on the first try, and retries with error messages plateaued near 65% by five attempts: LLMs are "not great at taking Dafny error messages".[103] Generate-and-check loops against a solver do far better. Reasoning LLMs plus Z3 counterexamples solved all 133 Code2Inv tasks, where the previous best was 107.[106] NeuroInv reached 99.5% on 150 Java programs.[107]
  - *Mo today:* bounded `for` loops ([[p11-loops-and-anonymous-functions|pick 11]]). The loops-vs-tier-3 tension is raised on [[bosque]].
  - *Verdict:* **open**, with a partial answer. Agents *can* write invariants when tier 3 hands counterexamples back. The evidence comes from benchmark-sized programs, not real ones.

- **Contract shapes that LLMs discharge.** Vericoding success by language: Dafny 82.2%, Verus 44.2%, Lean 26.8%.[100] Verus scores lower partly because it separates ghost types from native Rust types, "requiring verification of machine-level complexities such as overflow handling".[100] "More preconditions ease verification by providing assumptions, while more postconditions increase difficulty". Helper definitions create interdependent obligations.[100] Adding natural-language descriptions "does not significantly improve performance", and pure Dafny verification rose from 68% to 96% in a year.[100] The benchmark also had to detect cheating, such as `assume(false)` or edited postconditions.[100]
  - *Mo today:* direction 22 cites the Dafny-level number as Mo's expectation. Integers are explicitly sized everywhere ([[q04-integer-types-and-overflow|Q4]]). There is no `assume`, and no escape hatch ([[q16-escape-hatch|Q16]]).
  - *Verdict:* **steal** the shape guidance (below). ⚠️ The overflow finding needs care (below).

- **Dafny as a hidden intermediate language.** The LLM writes Dafny, the verifier checks it against agreed specs, and the result compiles to the user's language.[101] In the authors' motivating example, an LLM given failing tests sometimes "modified the provided test cases to fit its faulty implementation".[101]
  - *Mo today:* Mo is meant to be both the verified language and the shipped one ([[d02-spec-altitude|direction 2]]). Weakening a `never` pulls a human in ([[d20-human-pulled-in-when-shape-changes|direction 20]]).
  - *Verdict:* **already have** the idea without the translation step. **Open:** tests and `ensures` need the same protection as `never`.

## What it gives up

- **Full proof, mostly.** SPARK itself advises Platinum only for "the highest integrity" parts.[104] Mo's `proofs(k of n)` accepts the same partiality ([[q06-verified-line|Q6]]).
- **Honest code, at a risk.** The guidance warns against "pleasing the tools", meaning changing the program to suit the prover.[104] Agents will do this unless the laws forbid it.
- **Proof effort grows with size.** DafnyBench success falls as the code to verify and the hints needed grow.[103]

## Evidence

- **Vericoding (12,504 specs):** Dafny 82.2%, Verus 44.2%, Lean 26.8%. Claude Opus 4.1 was best on Dafny and GPT-5 on Verus and Lean.[100]
- **DafnyBench:** best about 68% on 782 programs (Claude 3 Opus). About 54% on the first try, then diminishing returns from error feedback.[103]
- **Marmaragan:** 50.7% of SPARK annotation tasks. The best budgets were 6 parallel attempts with 1 retry, or 4 with 2.[102]
- **Loop invariants with a solver loop:** 133/133 on Code2Inv,[106] 99.5% on 150 Java programs.[107]

## What Mo should take from this

- ⚠️ **Tension between [[q04-integer-types-and-overflow|Q4]] (sized integers only) and [[d22-rust-plus-refinements-types|direction 22]]'s Dafny-level expectation.** Vericoding attributes part of Verus's 44% to machine-integer obligations such as overflow.[100] Mo's sized integers may land it nearer Verus than Dafny. Options: unbounded mathematical integers inside contracts only; accept a lower tier-3 rate; or measure first ([[d28-nothing-final-until-measured|direction 28]]). Not resolved here.
- **Partial answer to the [[bosque]] ⚠️ (loops vs tier 3):** tier 3 runs a generate-and-check loop for loop invariants, with solver counterexamples fed back to the agent.[106][107] Measure it on the Mo corpus.
- **Proposal:** add a Silver-style entry, "no runtime errors proven (k of n)", to the `verified:` vocabulary.[104]
- **Proposal:** contract-shape guidance in the error catalog ([[q09-compiler-diagnostics|Q9]]): prefer more `requires` and smaller `ensures`, and avoid long helper chains in specs.[100]
- **Proposal:** a proof cache keyed by declaration hash plus callee contract hashes.[105]
- **Evidence for [[q09-compiler-diagnostics|Q9]]:** raw verifier errors teach LLMs poorly, with retries plateauing fast.[103] So tier-3 failures should reach the agent as structured diagnostics with a counterexample and candidate fixes, not as prover output.
- **Proposal:** tier 3 rejects any change that edits a contract or test while its proof is failing, the equivalent of vericoding's cheating detection.[100]
- **Question for Robert:** when an agent changes a function body, must its `test` and `ensures` blocks stay untouched in that same change? This extends direction 20 from `never` to all of the spec, and answers the test-rewriting failure seen with Dafny.[101]

## Related
- [[language-landscape]]
- [[d03-source-carries-its-evidence]]
- [[d22-rust-plus-refinements-types]]
- [[q08-verification-tiers]]
- [[q06-verified-line]]
- [[p08-contracts]]
- [[bosque]]
- [[unison]]

## Sources

[100] https://arxiv.org/abs/2509.22908 — A benchmark for vericoding: formally verified program synthesis from formal specifications
[101] https://arxiv.org/abs/2501.06283 — Dafny as Verification-Aware Intermediate Language for Code Generation
[102] https://arxiv.org/abs/2502.07728 — Verifying LLM-Generated Code in the Context of Software Verification with Ada/SPARK (Marmaragan)
[103] https://arxiv.org/abs/2406.08467 — DafnyBench: A Benchmark for Formal Software Verification
[104] https://docs.adacore.com/spark2014-docs/html/ug/en/usage_scenarios.html — SPARK User's Guide: Applying SPARK in Practice (adoption levels)
[105] https://www.adacore.com/languages/spark — SPARK (AdaCore)
[106] https://arxiv.org/abs/2508.00419 — Loop Invariant Generation: A Hybrid Framework of Reasoning-optimised LLMs and SMT Solvers
[107] https://arxiv.org/abs/2512.15816 — A Neurosymbolic Approach to Loop Invariant Generation via Weakest Precondition Reasoning (NeuroInv)
[108] https://portal.fis.tum.de/en/publications/autofy-automated-synthesis-of-formally-verified-code — Autofy: Automated Synthesis of Formally Verified Code (TUM, 2026)
[109] https://docs.adacore.com/spark2014-docs/html/ug/en/source/subprogram_contracts.html — SPARK User's Guide: Subprogram Contracts
[110] https://docs.adacore.com/spark2014-docs/html/ug/en/gnatprove.html — SPARK User's Guide: Formal Verification with GNATprove
