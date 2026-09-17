---
title: "ML / Standard ML / OCaml — Type Inference Enters the Bloodstream"
created: 2026-09-13
updated: 2026-09-17
type: research
tags: [history, languages]
sources:
  - "../../raw/plang-history-2026-09/deep-dives/04_ml.md"
---
# ML / Standard ML / OCaml — Type Inference Enters the Bloodstream


## Headline

Robin Milner started ML at Edinburgh in 1973 as the *Meta Language* for the LCF theorem prover — its job was to write proof tactics that could not produce bogus theorems ([Wikipedia: ML](https://en.wikipedia.org/wiki/ML_(programming_language))). To make that safe, Milner invented what became **Hindley–Milner type inference**: principal types without programmer annotations, published in his 1978 paper *A theory of type polymorphism in programming*.

## The three ideas that shaped everything

- **Type inference.** You write code; the compiler discovers the most general type. Every typed FP language since — Haskell, Rust, Scala, F#, Swift, OCaml — inherits some form.
- **Algebraic data types + pattern matching.** Sum types with case analysis; the exhaustiveness check is a proof that every branch was considered. Rust's `enum` and `match` are ML's, unchanged in essence.
- **Modules as a language layer.** Standard ML's module system (MacQueen, 1983+) is functors and signatures — parameterized modules with abstract type sealing. Still one of the most powerful module systems ever shipped.

## The lineage

- **ML** (Milner, 1973) — for LCF proofs.
- **Standard ML** (Milner, MacQueen, Tofte; formal *Definition* 1990) — first mainstream language with a full mathematical semantics.
- **Caml → OCaml** (INRIA; Leroy et al., 1996) — objects added; Jane Street adopts it commercially.
- **F#** (Syme, 2005) — SML/OCaml lineage on .NET.
- **ReasonML / ReScript** (Facebook, 2016+) — OCaml with JS-family syntax for the browser.

## What Mo takes

- **Algebraic data types + exhaustive `match`.** Central to [[d11-statically-typed]] and [[q05-option-and-no-nil]].
- **Bidirectional type checking.** Mo's type system is aimed at "System F + refinements" with bidirectional propagation — an ML descendant, not a Hindley–Milner clone (see [[q13-implementation-language]] and [[plang-decision-matrix|the decision matrix]]).
- **Functors, cautiously.** SML's module system is powerful but Mo's package model ([[d34-packages-are-recipes]]) leans toward simpler capability-declared manifests than full functor calculus.

## What Mo refuses

- **Global type inference.** Full HM makes error messages nonlocal and confuses agents. Bidirectional checking with annotations at function boundaries wins.
- **The dual namespace of SML.** Types and values in the same namespace is simpler for humans and agents alike.

  17 Sep 2026: Mo went the other way — [[grammar|the grammar]] separates type and value positions lexically.
- **Impure by default.** OCaml permits arbitrary side effects; Mo channels effects through capabilities ([[d15-effects-via-capabilities]]).

## The lasting lesson

ML proved that a language could be *both* practical and formally defined. Standard ML's 1990 *Definition* is the model Mo aims to imitate — a language whose semantics are precise enough that an agent can reason about them without running the program.

## Sources

- [Full deep-dive](../../raw/plang-history-2026-09/deep-dives/04_ml.md)
- [Wikipedia: ML](https://en.wikipedia.org/wiki/ML_(programming_language))
- [HOPL IV: The History of Standard ML](https://hopl4.sigplan.org/details/hopl-4-papers/16/The-History-of-Standard-ML)

## Related

- [[haskell]] — the pure-lazy branch of the ML family
- [[rust]] — ML's algebraic types with linear resources
- [[koka]] — effect handlers on an ML core
- [[d11-statically-typed]]
- [[d22-rust-plus-refinements-types]]
