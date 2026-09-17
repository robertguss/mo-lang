---
title: "C++ — Zero-Overhead Abstraction and Its Discontents"
created: 2026-09-13
updated: 2026-09-17
type: research
tags: [history, languages]
sources:
  - "../../raw/plang-history-2026-09/deep-dives/07_cpp.md"
---
# C++ — Zero-Overhead Abstraction and Its Discontents


## Headline

Bjarne Stroustrup began "C with Classes" at Bell Labs in April 1979 to combine Simula's class facilities with C's efficiency ([Stroustrup, HOPL-II C++ paper](https://www.stroustrup.com/hopl2.pdf)). The name "C++" was Rick Mascitti's suggestion (December 1983). First commercial release 1985. ISO C++ committee (WG21) convened in Lund, June 1991.

## The one big idea

**Zero-overhead abstraction.** You do not pay at runtime for the abstractions you do not use, and abstractions you do use compile down to code as efficient as hand-written low-level code. This principle is the reason C++ powers browsers, games, HFT systems, and every AAA engine.

## What C++ got right

- **Destructors and RAII.** Deterministic resource management via scope. The single best idea in the language and the direct ancestor of Rust's ownership.
- **Templates.** Parametric polymorphism with monomorphization. When they work they are unbeatable; when they don't the error messages are legendary.
- **STL (Stepanov).** Generic algorithms over iterators. The intellectual peak of C++.
- **`constexpr`.** Turing-complete compile-time evaluation — the modern feature that finally displaced the preprocessor.

## What C++ got wrong (or admitted grudgingly)

- **The preprocessor stayed.** Every attempt at modules took decades; C++20 modules are still not universally adopted.
- **Undefined behavior compounds.** Multiple inheritance, virtual bases, ADL, template ambiguities — each fine alone, together they produce a specification even the committee cannot fully summarize.
- **Ecosystem fragmentation.** No standard package manager. Every large project vendors its own build system.
- **The learning cliff.** Effective C++ is a book series. Multiple books.

## What Mo takes

- **RAII → linear resources.** Mo's ownership model owes a direct debt to C++'s scope-bound destructors, filtered through Rust ([[rust]]).

  17 Sep 2026: Mo took neither — there are no destructors and no RAII; memory is a per-process region freed at the process's end (chapter 7).
- **`constexpr` → comptime.** Mo will have compile-time evaluation for metaprogramming, not text macros ([[zig]] is the direct inspiration).
- **Templates → constrained generics.** Parametric polymorphism with explicit trait/bound constraints, not duck typing.

## What Mo refuses

- **Inheritance and virtual dispatch.** [[d06-never-oop]]. Composition via traits and data.
- **Implicit conversions and overload resolution.** Agents cannot reason about "which overload got picked, and why?"
- **Header-plus-linker.** Modules from day one; see [[d34-packages-are-recipes]].
- **Undefined behavior as a compiler-optimization tool.** Mo prefers checked semantics with escape hatches at capability boundaries.

## The lasting lesson

C++ demonstrates that a language can succeed enormously *and* be a cautionary tale. Stroustrup's HOPL papers are a masterclass in the discipline of *not* removing anything — every C++ feature has users, so every feature stays, and the accretion never stops. Mo's counter-commitment: keep the language small, ship an "epochs"-style versioning story if needed, but do not let the surface area grow unchecked.

## Sources

- [Full deep-dive](../../raw/plang-history-2026-09/deep-dives/07_cpp.md)
- [Stroustrup, HOPL-II C++ paper](https://www.stroustrup.com/hopl2.pdf)
- [Stroustrup, "Thriving in a Crowded and Changing World: C++ 2006-2020" HOPL IV](https://www.stroustrup.com/hopl20main-p5-p-bfc9cd4--final.pdf)

## Related

- [[c]] — the substrate C++ never fully left behind
- [[rust]] — the RAII descendant that ships with checks
- [[zig]] — the "start over from C" alternative
- [[d24-compile-to-c-via-zig]]
