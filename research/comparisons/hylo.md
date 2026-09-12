---
title: "Mo vs Hylo"
created: 2026-09-12
updated: 2026-09-12
type: comparison
tags: [research, state, types]
sources: [raw/articles/hylo-introduction.md, raw/articles/hylo-tour-functions.md, raw/articles/hylo-tour-bindings.md, raw/articles/hylo-tour-subscripts.md, raw/articles/hylo-tour-concurrency.md, raw/articles/hylo-spec-trait-conformance.md, raw/articles/hylo-new-compiler-repo.md, raw/articles/hylo-compiler-repo.md, raw/papers/implementation-strategies-mutable-value-semantics-jot22.md, raw/papers/native-implementation-mutable-value-semantics.md]
confidence: medium
---

# Mo vs Hylo

**One line:** the direct source of Mo's `var` and `inout` ([[d13-local-var-and-inout|direction 13]]); on the list to pin down mutable value semantics precisely (conventions, projections, exclusivity) and to borrow its answers on generics and concurrency.

## What it is (status as of Sep 2026)

Hylo "leverages mutable value semantics and generic programming for high-level systems programming". It "is under active development and is not ready to be used yet".[62] Most effort now goes into a new compiler, `hylo-new`,[69] a Swift codebase started in October 2024 that builds on LLVM.[66] The theory comes from Racordon, Shabalin, Zheng, Abrahams and Saeta.[68] Unsafe code exists, but only "by explicit, auditable opt-in".[62]

## The ideas, one by one

- **Ban sharing, not mutation.** Mutable value semantics "bans sharing instead of mutation". In its purest form, references are second-class: "only created implicitly, at function boundaries, and cannot be stored in variables or object fields".[68] So two variables can never share mutable state.
  - *Mo today:* a `var` "can never be aliased, never escapes its function" ([[d13-local-var-and-inout|direction 13]]). Structs change only through `var updated = charge` ([[p07-types-struct-enum-refinement|pick 7]]).
  - *Verdict:* **already have.** Direction 13 is mutable value semantics in its strict form.

- **Four parameter conventions.** `let` is the default: immutable, and it can't escape without `.copy()`. `inout` mutates in place. `sink` transfers ownership, so the caller loses the value. `set` initializes an uninitialized value.[63] Mutation is marked with `&`, including at the call site:[63]
  ```hylo
  fun offset_inout(_ target: inout Vector2, by delta: Vector2) {
    &target.x += delta.x
  }
  offset_inout(&v, by: (x: 1, y: 1))
  offset_inout(&v, by: v)   // error: overlapping `inout` access to `v`
  ```
  - *Mo today:* immutable by default plus `inout` ([[d13-local-var-and-inout|direction 13]]). No `sink`, no `set`, and no call-site marker decided.
  - *Verdict:* **already have** `let` and `inout`. **Reject** `sink` and `set` as syntax: Perceus's reuse at refcount 1 ([[d10-immutable-by-default|direction 10]]) is meant to find moves without annotations, a hypothesis to measure. **Open:** does a Mo call site show that an argument is mutated?

- **Exclusivity is the law.** An `inout` argument must be unique. Inside the callee it behaves "as though it had been declared to be a local `var`, with a value that is truly independent from everything else". A `let` parameter can't be changed "by any other means during the call", which rules out data races.[63]
  - *Mo today:* implied by "never aliased" in [[d13-local-var-and-inout|direction 13]], but not stated as a checked rule.
  - *Verdict:* **steal** the exact rule and error ("overlapping `inout` access") for Mo's error catalog ([[q09-compiler-diagnostics|Q9]]).

- **Projections instead of references.** A subscript "does not return a value, it projects one", granting temporary read or write access.[62] `emphasize(&longer_of[&x, &y])` mutates whichever string is longer, with no lifetime annotations.[62] An `inout` binding projects part of a value: `inout x = &point.x`.[64] `yielded` parameters adapt to how the caller uses the result.[65]
  - *Mo today:* nothing comparable. Process `update` writes `state.count += 1` ([[p10-process|pick 10]]).
  - *Verdict:* **open.** Mo will need *some* in-place path into a big value, such as `state.jobs[id].attempts += 1` inside a queue process. Full user-defined subscripts are probably more than Mo wants.

- **Coherence, stated in one paragraph.** "A type may have at most one source of conformance to a specific trait." A conformance may be exposed outside a module only if the type or the trait is declared there. A private conformance to an imported trait is fine.[71]
  ```hylo
  public type A {}
  conformance A: M.T {}  // OK: conformance is private
  public type C: M.T {}  // error: cannot expose conformance to imported trait
  ```
  - *Mo today:* `trait` plus `impl … for` ([[p15-methods-traits-generics|pick 15]]). Where an `impl` may live is the open question raised on [[rust]] and [[roc]].
  - *Verdict:* **steal.** It is a complete, short answer to that question.

- **Concurrency without colors or actors (planned).** The design is "still under design". Its principles: concurrent code has "the same syntax/semantics as non-concurrent code", "no function colouring", no `actor` abstractions, and structured concurrency. "Functions have one entry point and one exit point, regardless of the concurrency expressed in it", and there are no mutexes.[70]
  - *Mo today:* no function coloring ([[d16-direct-style-io|direction 16]]). The process *is* Mo's actor ([[d14-processes-are-the-only-identity|direction 14]]). `Task.run(fn … end, within:)` is planned sugar ([[q07-process-api|Q7]]).
  - *Verdict:* **already have** no coloring. **Reject** Hylo's no-actors stance, because Mo chose processes. **Steal** "one entry, one exit" for `Task.run`: a task can't outlive the function that started it.

## What it gives up

- **Stored references.** Graphs and back-pointers need indices or explicit copies.[68] Mo accepts the same cost, with processes as the only identity.
- **Quiet code.** Every mutation carries `&`, and escaping a `let` needs `.copy()`.[63] Mo has chosen quieter syntax so far ([[p03-bindings|pick 3]]).
- **Usability today.** Hylo is not ready to use, and its compiler is being rewritten.[62][69]
- **A safe-only language.** Hylo keeps an opt-in unsafe escape hatch.[62] Mo puts all unsafe code in platforms ([[q16-escape-hatch|Q16]]).

## Evidence

- **Performance of mutable value semantics:** the JOT 2022 paper benchmarks handwritten and randomly generated programs across Swift, Swiftlet, Scala and C++.[67] Its numbers were not in the extracted text.
- **The humans-and-aliasing cost MVS avoids:** see the Bronze trial on [[austral]].
- **Adoption:** none, since Hylo is "not ready to be used yet".[62]
- **LLMs and MVS:** no evidence found this pass.

## What Mo should take from this

- **Proposal:** adopt Hylo's coherence rule for Mo traits. At most one `impl` per type/trait pair. A `pub` impl only in the module of the type or the trait. Private impls allowed.[71] This closes the open question from [[rust]] and [[roc]] without Roc's loss of retroactive impls.
- **Question for Robert:** mark mutation at the call site? The options are nothing (today's examples), Hylo's `&v`, or a word (`inout v`). An agent reading a call can then see which arguments change.
- **Question for Robert:** allow nested place paths (`state.jobs[id].attempts += 1`) as Mo's only form of projection, with no user-defined subscripts?
- **Proposal:** no `sink` or `set` keywords. The compiler infers moves through Perceus. Count copies in the benchmark suite to check this ([[d28-nothing-final-until-measured|direction 28]]).
- **Proposal:** add "overlapping `inout` access" as an error code with Hylo's example ([[q09-compiler-diagnostics|Q9]]).
- **Proposal:** make `Task.run` structured: the task ends before its function returns.[70]
- **No contradiction found** with directions 13, 14 or 16.

## Related
- [[language-landscape]]
- [[d13-local-var-and-inout]]
- [[p15-methods-traits-generics]]
- [[d16-direct-style-io]]
- [[q07-process-api]]
- [[rust]]
- [[roc]]
- [[austral]]

## Sources

[62] https://hylo-lang.org/introduction — Introduction to Hylo
[63] https://docs.hylo-lang.org/language-tour/functions-and-methods — Hylo language tour: Functions and methods (parameter conventions)
[64] https://docs.hylo-lang.org/language-tour/bindings — Hylo language tour: Bindings
[65] https://hylo-lang.org/docs/user/language-tour/subscripts — Hylo language tour: Subscripts
[66] https://github.com/hylo-lang/hylo-new — hylo-new: the new Hylo compiler (GitHub)
[67] https://kyouko-taiga.github.io/assets/papers/jot2022-mvs.pdf — Implementation Strategies for Mutable Value Semantics (Racordon et al., JOT 2022)
[68] https://arxiv.org/abs/2106.12678 — Native Implementation of Mutable Value Semantics (Racordon, Shabalin, Zheng, Abrahams, Saeta)
[69] https://github.com/hylo-lang/hylo — Hylo compiler repository (GitHub)
[70] https://docs.hylo-lang.org/language-tour/concurrency — Hylo language tour: Concurrency
[71] https://github.com/hylo-lang/specification/blob/main/spec.md — Hylo Language Specification (trait conformance)
