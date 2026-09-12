---
title: "Mo vs Rust"
created: 2026-09-12
updated: 2026-09-12
type: comparison
tags: [research, types, compiler]
sources: [raw/articles/rust-1-98-released.md, raw/articles/state-of-rust-survey-2025.md, raw/articles/rust-compiler-performance-survey-2025.md, raw/articles/rust-next-trait-solver-nightly-2026.md, raw/articles/rust-polonius-alpha-nightly-2026.md, raw/papers/zhu-rust-learning-challenges-icse22.md, raw/papers/rustassistant-llm-fix-compile-errors.md, raw/papers/crust-bench-c-to-safe-rust.md, raw/articles/google-rust-in-android-2025.md, raw/articles/itpro-bergstrom-google-rust-productivity.md]
confidence: medium
---

# Mo vs Rust

**One line:** the source of Mo's type system ([[d22-rust-plus-refinements-types|direction 22]]) with lifetimes removed; on the list to be exact about what Mo keeps, what it drops, and what each drop costs.

## What it is (status as of Sep 2026)

Rust 1.98.0 shipped on 20 August 2026.[29] The 2025 State of Rust survey had 7,156 completed responses. Slow compiles and storage use were "still up there" among problems, and concern persists "about the language becoming more and more complex".[28] Two core compiler components are being replaced in 2026. The next-generation trait solver went on by default on nightly after nearly four years of work, "the largest single change to the Rust compiler since its initial release".[31] A new borrow checker, Polonius Alpha, went on nightly in August, aiming at stable later in the year.[32] At Google, memory-safety bugs in Android fell below 20% of all vulnerabilities for the first time in 2025.[30]

## The ideas, one by one

- **Enums with data, exhaustive `match`, `Result`/`Option`, no null.** Absence and failure are ordinary values that the compiler forces you to handle. `?` propagates an error.
  - *Mo today:* the same core: `enum` with data ([[p07-types-struct-enum-refinement|pick 7]]), exhaustive `case` ([[p05-pattern-matching|pick 5]]), `Option` and no nil ([[q05-option-and-no-nil|Q5]]). A prefix `try` replaces postfix `?`, and there is no `unwrap` ([[p06-results-and-propagation|pick 6]]).
  - *Verdict:* **already have.** This is the part of Rust nobody complains about. Go's 2025 survey cites it as the envy ([[go]]).

- **Traits, and the solver behind them.** Rust's traits drive generics, operators, auto traits and `impl Trait`. The trait solver rewrite took about four years and fixes more than 200 known issues.[31]
  - *Mo today:* `trait` / `impl … for`, bounds only through `where`, no inheritance, no default overriding, no trait objects in v1 ([[p15-methods-traits-generics|pick 15]]). [[d22-rust-plus-refinements-types|Direction 22]] says "without the deep solver machinery".
  - *Verdict:* **already have** the smaller shape, and the size of the rewrite supports keeping it small. **Open:** Mo hasn't said *where* an `impl` may live. Rust calls this *coherence*: two packages must not both implement the same trait for the same type.

- **Ownership, borrowing, lifetimes.** Rust has one owner per value, and either many shared borrows or one mutable borrow. Lifetimes prove borrows don't outlive their owner. Even after NLL, a borrow returned from one `match` arm is treated as living for the whole function. Polonius Alpha exists to accept code like this:[32]
  ```rust
  match map.get_mut(&key) {
      Some(value) => value,             // borrow returned here...
      None => { map.insert(key, v); … } // ...still "live" here under NLL
  }
  ```
  - *Mo today:* no references at all. `var` has mutable value semantics, plus `inout` ([[d13-local-var-and-inout|direction 13]]). Processes are the only identity ([[d14-processes-are-the-only-identity|direction 14]]).
  - *Verdict:* **reject** lifetimes (already decided in [[steal-list]]). The study below says lifetimes, not ownership, are where people fail.

- **`unsafe` as a scoped escape hatch.** Any crate may contain `unsafe` blocks. Android runs dedicated unsafe review and training.[30]
  - *Mo today:* no escape hatch in application code. The platform is the only unsafe layer ([[q16-escape-hatch|Q16]], [[q11-platform-and-stdlib|Q11]]).
  - *Verdict:* **already have**, stricter. Android's need for special unsafe review is the cost Mo avoids by putting unsafe code in one place.

- **Compile times as the tax.** The 2025 compiler-performance survey drew more than 3,700 responses.[27] 55% wait more than ten seconds for a rebuild. About 45% of former Rust users named long compile times among their reasons for leaving. The top complaint was incremental rebuilds: workspace changes cascade, linking is "always performed from scratch", and some compiler phases are not yet incremental.[27]
  - *Mo today:* compile speed is first-class ([[d23-compile-speed-first-class|direction 23]]). The edit loop is an interpreter that never links ([[d25-interpreter-for-the-edit-loop|direction 25]]). Tier 1 targets under 50ms ([[q08-verification-tiers|Q8]]).
  - *Verdict:* **already have** the requirement. **Steal** the measurement: Rust's pain is the *incremental* rebuild, not the clean build.

- **Macros and compile-time code.** Proc macros are a known compile-time sink. The Rust team wants tooling that answers "which (proc) macros take the longest time".[27]
  - *Mo today:* no macros and no build-time code execution ([[d30-supply-chain-security|direction 30]]).
  - *Verdict:* **already have** (rejected for both speed and supply-chain reasons).

## What it gives up

- **Learnability.** Lifetimes are the hard part (see Evidence). At Google, 8% of surveyed developers said they were still not productive in Rust.[34] Mo does not accept this cost.
- **Compile speed.** Rust lives with rebuild waits that more than half its users find too long.[27] Mo does not.
- **Complexity growth.** The 2025 survey names this as a persistent worry.[28] Mo's laws and small trait system are the counter-bet.
- **What Mo gives up by dropping borrows:** zero-copy references. Mo pays with copies and Perceus reference counting instead ([[d10-immutable-by-default|direction 10]]). That cost is a hypothesis under [[d28-nothing-final-until-measured|direction 28]], and it is not yet measured.
- **Release-mode overflow checks.** Rust gives these up for speed. Mo explicitly refuses ([[q04-integer-types-and-overflow|Q4]]).

## Evidence

- **Where humans fail (ICSE 2022):** in 118 safety-rule violations from Stack Overflow, 74 came from complex lifetime computation, 41 from ownership rules, and 3 were syntax.[25] Only 10.0% of survey participants "always" understood lifetime errors, against 39.6% for ownership errors. Enhanced error messages measurably helped.[25]
- **Payoff at scale (Android):** 1000x lower memory-safety vulnerability density than C/C++. Rust changes see about 4x fewer rollbacks, spend 25% less time in review, and need about 20% fewer revisions.[30]
- **Productivity (Google, 2024 talk):** rewrites from Go to Rust took about the same team size and time. C++ rewrites took less than half the effort. One in three developers were productive within two months.[34]
- **LLMs fixing Rust compile errors:** RustAssistant with GPT-4 fixed 92.59% of micro-benchmarks, 72% of Stack Overflow programs, and 73.63% of GitHub commits.[26]
- **LLMs writing whole programs in safe Rust:** on CRUST-Bench (100 C repos to safe Rust), the best model, o1, solved 15 single-shot.[33]

## What Mo should take from this

- **No contradiction found.** Rust's 2026 state supports [[d22-rust-plus-refinements-types|direction 22]] as written: keep the enums and matching, drop lifetimes, keep traits small.
- **Question for Robert:** coherence. May `impl Trait for Type` appear only in the module that defines the trait or the type? It needs an answer before packages ([[q17-package-management-and-supply-chain|Q17]]). Two dependencies must not be able to give `Money` two different `Comparable`s.
- **Proposal:** headline compile metric = p50/p95 time to diagnostics after a one-declaration change, measured on the corpus. Clean-build time is secondary.[27]
- **Proposal:** a benchmark pair that prices Mo's lack of borrows: the same program in Rust and in Mo, counting copies and reference-count operations ([[d28-nothing-final-until-measured|direction 28]]).
- **Proposal:** Mo's agent eval must include whole-program tasks. A per-error fix rate of about 73%[26] beside a 15% whole-repo rate[33] shows that fix loops alone flatter a language.
- **Proposal:** every Mo diagnostic names the rule and *both* conflicting sites. The ICSE result on better messages[25] is direct evidence for [[q09-compiler-diagnostics|Q9]]'s `why` field.

## Related
- [[language-landscape]]
- [[d22-rust-plus-refinements-types]]
- [[d23-compile-speed-first-class]]
- [[d13-local-var-and-inout]]
- [[q05-option-and-no-nil]]
- [[q16-escape-hatch]]
- [[p15-methods-traits-generics]]
- [[go]]

## Sources

[25] https://songlh.github.io/paper/survey.pdf — Learning and Programming Challenges of Rust: A Mixed-Methods Study (Zhu et al., ICSE 2022)
[26] https://www.microsoft.com/en-us/research/wp-content/uploads/2024/08/paper.pdf — RustAssistant: Using LLMs to Fix Compilation Errors in Rust Code (Microsoft Research)
[27] https://blog.rust-lang.org/2025/09/10/rust-compiler-performance-survey-2025-results — Rust compiler performance survey 2025 results
[28] https://blog.rust-lang.org/2026/03/02/2025-State-Of-Rust-Survey-results — 2025 State of Rust Survey Results
[29] https://blog.rust-lang.org/2026/08/20/Rust-1.98.0 — Announcing Rust 1.98.0
[30] https://blog.google/security/rust-in-android-move-fast-fix-things — Rust in Android: move fast and fix things (Google, 2025)
[31] https://blog.rust-lang.org/2026/08/21/enabling-next-solver-on-nightly — Enabling the next-generation trait solver on nightly (Rust blog, 2026)
[32] https://blog.rust-lang.org/2026/08/04/enabling-polonius-alpha-on-nightly — Enabling the next iteration of the borrow checker on nightly (Rust blog, 2026)
[33] https://arxiv.org/abs/2504.15254 — CRUST-Bench: A Comprehensive Benchmark for C-to-safe-Rust Transpilation
[34] https://www.itpro.com/software/development/google-devs-ditched-c-for-rust-heres-what-happened — Google devs ditched C++ for Rust (IT Pro, Bergstrom talk)
