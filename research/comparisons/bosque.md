---
title: "Mo vs Bosque"
created: 2026-09-12
updated: 2026-09-12
type: comparison
tags: [research, laws, verification]
sources: [raw/articles/bosquecore-repo.md, raw/articles/bosque-microsoft-archived-repo.md, raw/papers/regularized-programming-bosque-2019.md, raw/papers/toward-programming-languages-for-reasoning.md, raw/papers/toward-programming-languages-for-reasoning-part2.md, raw/articles/bosque-go-for-1-0.md, raw/articles/bosque-no-gc-has-gone-2026.md, raw/articles/bosquecore-discussion-66-status.md, raw/papers/catalpa-gc-bosque.md]
confidence: medium
---

# Mo vs Bosque

**One line:** the closest older cousin to Mo's laws ([[d04-style-rules-become-laws|direction 4]]): a language designed by *removing* features so that humans, solvers and AI agents can all reason about code. On the list for its specific removals, its verifier, and why a Microsoft Research project slowed down.

## What it is (status as of Sep 2026)

Bosque started at Microsoft Research in 2019 as "an experiment in regularized design".[93][94] The Microsoft repo is archived and development moved to `BosqueLanguage/BosqueCore`.[93] In August 2023 Mark Marron wrote: "I left MSR last year". He was about to join the University of Kentucky, and "Bosque will continue to be my (and my students) primary focus".[98] He declared 1.0 in November 2024. His own caveat: not "ready for primetime". There was a type checker and a simple JavaScript compiler, and "many features are marked todo"; the standard library is "very very minimal".[96] BosqueCore was last pushed on 3 September 2026 and has 198 stars.[92]

## The ideas, one by one

- **Design by removal.** The 2024 paper lists seven features that impede reasoning for humans, symbolic tools and LLMs: mutable state, implicit behaviours, hidden semantics, loops and recursion, indeterminate behaviour, temporarily broken data invariants, and reference equality.[95] Bosque's novelty is "the removal of problematic feature[s] and reduction in power" rather than new features.[95]
  - *Mo today:* the same stance. Style rules become compiler laws ([[d04-style-rules-become-laws|direction 4]]), "as simple as possible" ([[d27-simple-and-elegant-like-ruby|direction 27]]).
  - *Verdict:* **already have.** Bosque is proof the stance can be written down precisely, and a warning about how long a full stack takes.

- **No loops; lambdas that can't escape.** Bosque has no loop construct. Collection functors (`map`, `filter`, `find`…) replace loops so that no one has to invent loop invariants.[95] Lambdas "cannot be stored in local variables or returned" and "can capture arguments but cannot modify their values". A cited study found 87.5% of lambdas are passed directly as call arguments anyway.[95]
  ```
  function allPositive(...args: List<Int>): Bool {
      return args.allOf(pred(x) => x >= 0i);
  }
  ```
  - *Mo today:* bounded `for x in xs` loops and anonymous `fn(r) … end` ([[p11-loops-and-anonymous-functions|pick 11]]).
  - *Verdict:* **open.** Mo kept loops; see the ⚠️ below. **Steal** the lambda rule: it gives the closure-capture gap on [[koka]] a working precedent.

- **Referential transparency and full determinism.** Only primitive-like "key types" support equality, so no aliasing enters reasoning.[95] Under-specified behaviour, such as sort stability and map enumeration order, is removed, because it makes tests flaky and behaviour hard to follow.[95]
  - *Mo today:* values only, and processes are the only identity ([[d13-local-var-and-inout|direction 13]], [[d14-processes-are-the-only-identity|direction 14]]). Crashes replay from seed plus message log ([[d21-autonomous-crash-fixing|direction 21]]).
  - *Verdict:* **already have** no identity. **Steal** determinism as a stdlib law, because replay depends on it.

- **Validation with levels.** `assert`, `pre`/`post`, type invariants and `validate` for external data are built in. Each check has a level: `debug`, `test`, `release`, `spec`, or `safety`.[95] `spec` checks never run and exist for documentation and static tools; `safety` checks can never be optimized out.[95]
  - *Mo today:* `requires` / `ensures` / `invariant` / `never` ([[p08-contracts|pick 8]], [[p09-module-header-and-never|pick 9]]). Checks are on in every build ([[q04-integer-types-and-overflow|Q4]]).
  - *Verdict:* **already have** always-on safety. **Open:** Mo's base example has a `never` that loops over *all* refunds and charges. That can't run after every update, which is exactly what Bosque's `spec` level is for.

- **Small-model verification, not proofs.** Bosque maps code to a decidable logic fragment. The checker "will enumerate every possible error" and asks Z3 for either a failing input or `unsat`.[95] The argument: teams want "simple logical checks (asserts, pre/post, and data invariants)", not full proofs they can't debug.[95] Bosque 2.0 centres on a Small Model Verifier. It decides whether any small input triggers a runtime failure or a contract violation.[92]
  - *Mo today:* tier 3 runs an SMT prover in the background, a failed property is a counterexample, and `proofs(k of n)` is shown ([[q08-verification-tiers|Q8]], [[q06-verified-line|Q6]]).
  - *Verdict:* **steal** the framing: tier 3's job is counterexample search over a decidable fragment. The Z3 dependency problem noted on [[austral]] applies here too.

- **A runtime built for low variance.** One design precept is "design for low-variance execution … instead of optimizing for the best or average case".[92] The Catalpa collector uses immutability and the absence of cycles to promise bounded pauses and freedom from allocation starvation. The Bosque blog argues both are impossible for languages with mutability and cycles.[97][99]
  - *Mo today:* Perceus reference counting on immutable data ([[d10-immutable-by-default|direction 10]]). Every performance claim is measured ([[d28-nothing-final-until-measured|direction 28]]).
  - *Verdict:* **already have** the same lever (immutable, acyclic). **Steal** the metric: measure tail latency and memory variance, not means.

## What it gives up

- **Loops, and part of its audience.** Developer interviews showed "a strong preference for block-scoped flows and mutable variables". Bosque kept `var` and blocks by converting them to single-assignment form, which only works because the language has no loops.[95]
- **Flexible higher-order code.** No stored or returned lambdas means no currying.[95]
- **Momentum.** Bosque went from corporate lab to one professor and students,[98] and reached a 1.0 without a usable standard library or native compiler.[96]

**Why it slowed (Claude's reading of the sources, not a claim from them).** Bosque tried to build a language, a verifier, a new GC, an AOT runtime and a cloud API framework at once.[95][92] It left its funding institution midway.[98] Its 1.0 was a statement of stability, not usability.[96] None of that says the ideas failed.

## Evidence

- **Implementation size** at paper time: 30 kloc of TypeScript and 5 kloc of Bosque.[95]
- **Lambda usage:** 87.5% of lambdas are passed directly as call arguments (a study cited in the paper).[95]
- **AI case study:** qualitative only. Ensures clauses plus examples let generated code be screened, against a GPT-4/Copilot TypeScript completion that misread intent.[95] No numbers.
- **GC guarantees:** a theorem-level claim in the Catalpa paper. Production measurements were not found.[99]

## What Mo should take from this

- ⚠️ **Tension between [[p11-loops-and-anonymous-functions|pick 11]] (bounded `for` loops) and [[q08-verification-tiers|Q8]] (tier 3 discharges `requires` / `ensures` / `never`).** Bosque removed loops precisely because "generalized technique[s]" for loop invariants are impossible.[95] Mo keeps loops, so tier 3 must (a) have agents write loop invariants, (b) bound loop unrolling and settle for small-model checks, or (c) move to functors. The SPARK/Dafny comparison (next page) should report how well LLMs write invariants. Not resolved here.
- **Proposal:** Bosque's lambda rule for Mo anonymous functions: never stored or returned, captures read-only.[95] A capability captured by such a lambda can't outlive the call, so the enclosing signature still bounds its effects. That is option (c) on [[koka]], with a precedent.
- **Proposal:** a determinism law for the stdlib: stable sort, defined map iteration order, and no environment reads outside capabilities.[95] It is required for replay ([[d21-autonomous-crash-fixing|direction 21]]).
- **Question for Robert:** add a spec-only contract kind that is proved or sampled in tier 3 but never run at runtime? The base example's `never` over all refunds needs one.[95]
- **Proposal:** define tier 3 as small-model counterexample search over a decidable fragment.[92][95] It keeps `proofs(k of n)` honest.
- **Proposal:** the benchmark suite reports p99 latency and memory variance, not averages.[92]
- **Lesson (Claude's reading):** don't build the language, verifier and runtime all at once. Mo's interpreter-first order ([[d25-interpreter-for-the-edit-loop|direction 25]]) already guards against this.

## Related
- [[language-landscape]]
- [[d04-style-rules-become-laws]]
- [[p11-loops-and-anonymous-functions]]
- [[q08-verification-tiers]]
- [[p08-contracts]]
- [[koka]]
- [[austral]]

## Sources

[92] https://github.com/BosqueLanguage/BosqueCore — BosqueCore repository (README, 2.0 plans)
[93] https://github.com/microsoft/BosqueLanguage — microsoft/BosqueLanguage (archived)
[94] https://microsoft.com/en-us/research/publication/regularized-programming-with-the-bosque-language — Regularized Programming with the Bosque Language (Marron, MSR 2019)
[95] https://arxiv.org/abs/2407.06356 — Toward Programming Languages for Reasoning: Humans, Symbolic Systems, and AI Agents (Marron, Onward! 2024)
[96] https://bosquelanguage.github.io/2024/11/20/go-for-1_0.html — Go for 1.0!!! (Bosque blog, Nov 2024)
[97] https://bosquelanguage.github.io/2026/03/19/going-where-no-gc-has-gone.html — Going Where No GC Has Gone Before (Bosque blog, Mar 2026)
[98] https://github.com/BosqueLanguage/BosqueCore/discussions/66 — BosqueCore discussion #66: current state of the project
[99] https://arxiv.org/abs/2509.13429 — Catalpa: GC for a Low-Variance Software Stack (2025)
