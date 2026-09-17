---
title: "Haskell — Lazy, Pure, and Influential Far Beyond Its Adoption"
created: 2026-09-13
updated: 2026-09-17
type: research
tags: [history, languages]
sources:
  - "../../raw/plang-history-2026-09/deep-dives/05_haskell.md"
---
# Haskell — Lazy, Pure, and Influential Far Beyond Its Adoption


## Headline

A committee formed at FPCA '87 in Portland decided the fragmented world of non-strict pure FP needed a shared language ([Wikipedia: Haskell](https://en.wikipedia.org/wiki/Haskell)). Haskell 1.0 shipped on April 1, 1990 — "a date had to be chosen" ([Peyton Jones, *A History of Haskell: Being Lazy With Class*](https://simon.peytonjones.org/assets/pdfs/haskell-being-lazy-with-class.pdf)). Named after logician Haskell Curry. Not a joke, despite the release date.

## The three ideas that shaped everything

- **Purity.** No side effects in functions. Every effect — I/O, state, exception — lives inside a monadic type. This makes equational reasoning sound.
- **Type classes.** Wadler and Blott's principled ad-hoc polymorphism, later everywhere: Rust `trait`, Swift `protocol`, Scala `given`, Go's compromise interfaces.
- **Laziness as default.** Every value is a thunk until forced. This was the unifying commitment of the committee; it also produces the space-leak class of bugs that haunts every large Haskell system.

## What Mo takes

- **Purity as a type-level property.** Not the whole language, but the *effect region* around pure code — [[d15-effects-via-capabilities]] is Haskell's monadic segregation done via capabilities and handlers instead of return types.
- **Type classes / traits.** Some form of principled ad-hoc polymorphism is likely; Rust-style traits are the direct descendant Mo prefers.

  17 Sep 2026: built — `trait` and `impl` are in the language ([[p15-methods-traits-generics|pick 15]]).
- **The reasoning discipline.** Reason about programs as if they were mathematical values. This is exactly what [[d03-source-carries-its-evidence]] asks agents to do.

## What Mo refuses

- **Laziness by default.** Space leaks, opaque runtime behavior, no predictable performance — all disqualifying for a language agents ship into production. Strict evaluation ([[d10-immutable-by-default]]; link corrected 17 Sep 2026).
- **`IO` as a monad.** Monadic effect stacks are elegant but hard to compose in agent-written code. Algebraic effect handlers with capabilities are the successor ([[koka]]).
- **The committee culture of experimentation.** Haskell's motto — "avoid success at all costs" — is beautiful and unshippable. Mo optimizes for adoption.

## The lasting lesson

Haskell is the language whose ideas *everyone else* adopted. Type classes, Hindley-Milner extensions, GADTs, monad transformers, lens libraries, software transactional memory, QuickCheck property testing — all Haskell exports. But Haskell itself remains niche because the substrate (laziness, purity as language default) is too demanding.

Mo's read: **steal the ideas; steal them onto a strict, capability-flavored substrate that ships.**

## Two Peyton Jones quotes worth internalizing

> "Haskell's designers were united most strongly by laziness." — the whole language is a bet on one axis.

> "There will always be a suspicion that if Haskell had made more of an effort to be practical it would have been less influential." — the trade Mo refuses to make.

## Sources

- [Full deep-dive](../../raw/plang-history-2026-09/deep-dives/05_haskell.md)
- [Peyton Jones, *A History of Haskell: Being Lazy With Class*](https://simon.peytonjones.org/assets/pdfs/haskell-being-lazy-with-class.pdf)
- [Wikipedia: Haskell](https://en.wikipedia.org/wiki/Haskell)

## Related

- [[ml]] — the strict-eager branch of the same family
- [[koka]] — algebraic effects on an ML/Haskell substrate
- [[elixir]] — pattern matching and immutability without the monads
- [[d15-effects-via-capabilities]]
- [[d10-immutable-by-default]]
