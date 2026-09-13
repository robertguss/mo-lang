---
title: "Dependent Types — Agda, Idris, Lean"
created: 2026-09-13
updated: 2026-09-13
type: research
tags: [history, languages]
sources:
  - "../raw/plang-history-2026-09/deep-dives/15_dependent_types.md"
---

### Headline

Three languages pushed dependent types from theory into practice. All descend from Martin-Löf type theory and the Curry–Howard correspondence — types are propositions, programs are proofs.

- **Agda** (Ulf Norell, Chalmers; 2.0 in 2007) — research vehicle for dependent types *as a programming language*.
- **Idris** (Edwin Brady; 2007) — general-purpose dependently typed language, Haskell-flavored. Idris 2 (ECOOP 2021) adds **Quantitative Type Theory** (QTT) — linear + dependent types together ([arXiv 2104.00480](https://arxiv.org/abs/2104.00480)).
- **Lean** (Leonardo de Moura, MSR → AWS; launched 2013; Lean 4 in 2021) — proof assistant *and* efficient functional programming language. Now the substrate for the **mathlib** community mathematics library.

### The three ideas that shaped everything

- **Types can depend on values.** `Vec[T, n]` is a vector of length `n`, and `n` is a term. The type checker verifies length arithmetic at compile time.
- **Programs are proofs.** A total, terminating function of type `A → B` is a proof that `A` implies `B`. Running the program checks the proof.
- **Tactics.** Interactive proof scripts that construct programs incrementally. Lean's tactic language is a full metalanguage in its own right.

### The practical cost

- **Totality checking is undecidable.** Every dependent-type language requires termination proofs (structural recursion, sized types, well-founded orders) that ordinary programmers do not enjoy writing.
- **Compile times.** Type checking involves running arbitrary code at compile time.
- **Elaboration is opaque.** When the type checker fails, the error is often unreadable — a big chunk of hole-filling metavariables.

### What Mo takes — cautiously

Mo does *not* aim to be a dependently typed language. It aims to import the ideas that survive the ergonomics test:

- **Refinement types.** A restricted, decidable slice of dependent types: `Int where x > 0`. The type system Mo commits to is "System F + refinements" ([[d22-rust-plus-refinements-types]]), not full dependent types. SMT-solvable refinements are the sweet spot.
- **Proof-carrying artifacts.** [[d03-source-carries-its-evidence]] — Mo source can carry proof obligations discharged by SMT solvers or, at the highest tier, by explicit proofs.
- **QTT-style quantities.** Idris 2's approach to unifying linear resources with dependent types is directly relevant to combining Mo's capability system with its refinements.
- **[[q08-verification-tiers]].** Not every function needs a proof; ordinary code type-checks normally, and only capability-guarded or high-assurance functions incur the proof burden. Lean's model of "everything is a proof" is inverted: in Mo, proofs are opt-in.

### What Mo refuses

- **Universes and universe polymorphism.** Too much conceptual overhead for a general-purpose language.
- **Tactics as the primary programming interface.** Agents can generate tactic scripts, but the *default* programming model is direct code.
- **Full dependent elimination.** Refinements + SMT solving get most of the value at a fraction of the ergonomic cost.

### The lasting lesson

Dependent types demonstrate that the type system can carry arbitrary specifications — including full functional correctness. The open engineering question is *how much* proof burden to require by default. Mo's answer: **almost none**, with an escalating [[q08-verification-tiers]] ladder for code that needs stronger guarantees (capability-guarded FFI, cryptographic primitives, verified line functions).

Lean's success with mathlib also proves that a critical mass of a community can be persuaded to write proofs when the tooling is good enough. That is inspiration, not obligation.

## Related

- [[haskell]] — the ancestor most Idris users came from
- [[ml]] — the type-theory root of the family
- [[koka]] — a related "types + effects" strand
- [[d22-rust-plus-refinements-types]]
- [[q08-verification-tiers]]
- [[austral]] — linear types without full dependency
- [[spark-ada-and-dafny]] — the SMT-backed verification strand

## Sources

- [Full deep-dive](../raw/plang-history-2026-09/deep-dives/15_dependent_types.md)
- [Wikipedia: Agda](https://en.wikipedia.org/wiki/Agda_(programming_language))
- [Wikipedia: Idris](https://en.wikipedia.org/wiki/Idris_(programming_language))
- [Wikipedia: Lean](https://en.wikipedia.org/wiki/Lean_(proof_assistant))
- [Brady, "Idris 2: Quantitative Type Theory in Practice"](https://arxiv.org/abs/2104.00480)
- [Lean 4 paper](https://lean-lang.org/papers/lean4.pdf)
