---
title: "The eight camps of language design"
created: 2026-09-13
updated: 2026-09-17
type: deep-dive
tags: [history, research]
sources:
  - "../raw/plang-history-2026-09/camps/design_camps_and_tradeoffs.md"
contested: true
contradictions: [01-premise, d24-compile-to-c-via-zig, q13-implementation-language]
---
# The eight camps of language design

> **17 Sep 2026.** This page is the 13 Sep synthesis of an external research run. The Mo it describes — brace syntax, effect rows, a Rust implementation, a package registry, an RFC process — was never Mo's design. Mo's decisions are the spec chapters under `spec/design-v0/` and the [[decision-log]]. Read this page as landscape only.

## Headline

Language design is not one activity but a family of them, and the designers disagree — often bitterly — about what a language is *for*. The raw report maps this landscape as eight camps: paradigm, type system, memory, concurrency, syntax, compilation, philosophy, and ecosystem. Each camp is a coherent bundle of beliefs and an accepted trade-off.

## Three findings that shape everything

- **The camps compose more than they collide.** A language can be imperative-syntax, functional-semantics, statically typed, capability-secure, and CSP-concurrent. Mo takes a position on every axis and refuses the false choice that any single camp forces.
- **The static-vs-dynamic wars were about the wrong question.** Harper's "dynamic typing is a special case of static typing" (with a Universal type) reframes the argument. Hickey's counter is about *complecting* concerns, not types themselves. Mo sides with static + refinements ([[d11-statically-typed]], [[d22-rust-plus-refinements-types]]).
- **Ecosystem philosophy (Camp H) is now more consequential than paradigm (Camp A).** In 2026, package-manager design, supply-chain defense, and dependency-resolution choice have a bigger effect on a language's fate than its expression semantics.

## Camp A — Paradigm

| Sub-camp | Exemplars | Mo position |
|---|---|---|
| A1 Imperative | C, Zig, Odin, Jai | Syntax only |
| A2 OO (4 flavors) | Simula/C++/Java, Smalltalk, prototype, actor | Rejected — [[d06-never-oop]] |
| A3 Pure functional | Haskell, Elm, Roc | Semantics inspiration |
| A4 Impure functional | ML, OCaml, Elixir, Clojure | **Primary target** — [[d07-elixir-flavored-functional]] |
| A5 Logic | Prolog, Datalog | Not core |
| A6 Concatenative | Forth, Factor | Not core |
| A7 Array | APL, J, K, BQN | Not core |
| A8 Dataflow / reactive | Lucid, Esterel, FRP | Studied |
| A9 Constraint | Oz, MiniZinc | Not core |
| A10 Actor | Erlang, Pony, Akka | **Concurrency model** — [[d12-concurrency-at-the-edges]] |

## Camp B — Type system

Fourteen distinct positions in the raw report. Mo's is a hybrid:

- Static nominal (B5) as the base
- Hindley-Milner descendant (B6) with bidirectional propagation, not full inference
- Refinement types (B8) via SMT solvers
- Linear/affine types (B9) for capabilities and resources
- Effect types (B11) via capability-passing — see [[d15-effects-via-capabilities]]
- Ownership + borrowing (B13) informed by Rust and Vale
- Capability types (B14) informed by Pony, Wyvern, Austral

Explicitly out of scope: dependent types (B7) as default, gradual typing (B3), untyped (B1), full HM inference (B6) as the *only* type-checking mode.

## Camp C — Memory

- C1 Manual (C, Zig) — kept as a capability-guarded escape.
- C2 RAII (C++, Rust) — the model Mo inherits at scope boundaries.
- C3 Refcounting (Swift, Obj-C ARC, CPython) — considered for interop.
- C4 Tracing GC (Java, Go) — rejected as language default; possible per-runtime.
- **C5 Regions (Cyclone, MLKit, Vale)** — Mo's preferred primary model, backed by capabilities.
- C6 Ownership + borrowing (Rust) — informing but not identical.
- C7 Linear types for memory (Austral, Granule) — related to capabilities.
- C8 Hybrid (Nim, Roc platforms, Swift ownership) — Mo is a hybrid.
- C9 No allocation (MISRA-C) — capability-declared for embedded targets.

## Camp D — Concurrency

- D1 Threads + locks — the substrate to avoid exposing.
- D2 CSP + channels (Go) — direct inspiration.
- **D3 Actors (Erlang, Elixir, Pony)** — [[d08-beam-qualities-without-the-beam]].
- D4 STM (Clojure, GHC Haskell) — capability-declared runtime, not language core.
- D5 async/await — likely surface syntax over structured concurrency.
- **D6 Structured concurrency (Trio, Swift, Kotlin coroutines)** — the primary model.
- D7 Data parallel (Futhark) — capability-declared kernel dispatch.
- D10 Effect-based (Koka, OCaml 5) — informs [[d15-effects-via-capabilities]].

## Camp E — Syntax

- E1 C-family curly braces — Mo's likely surface. LL(1)-friendly.
- E2 ML-family expression-oriented — semantics inspiration.
- E3 Lisp S-expressions — rejected for tooling reasons.
- E4 Python indentation — rejected for agent-diff robustness.

Guy Steele's *Growing a Language* argues syntax extensibility matters. Mo disagrees: a stable grammar is more valuable than user-defined syntax when agents write code.

## Camp F — Compilation

- F1 AOT to native — the release mode.
- F3 Interpretation — the edit-loop mode.
- **F7 Compilation to C** (Nim, Chicken, historical Vala) — [[d24-compile-to-c-via-zig]] via `zig cc`.
- F6 WebAssembly — a plausible additional target.
- F5 VM bytecode — considered but not committed.
- F2 JIT — deferred; not required for the first release.

## Camp G — Philosophy

Twelve sub-camps mapped in the raw report. Mo's position stitches together:

- G3 Wirthian minimalism — small core.
- G6 "Simple Made Easy" (Hickey) — decompose complected concerns.
- G7 Zero-cost abstractions (C++, Rust) — where they don't inflate the language.
- **G11 Agent-authored language design (emerging)** — the deliberate Mo bet, see [[d01-agents-write-the-code]].
- G12 Capability-safe languages — the security posture.
- G13 Verified languages (F*, Verus) — capability-guarded escalation, [[q08-verification-tiers]].

Explicitly refused: G1 Worse-is-better (Gabriel) as an *excuse*; G4 kitchen-sink maximalism; G5 "Blub paradox" as a design principle.

## Camp H — Ecosystem

- H1 Package-manager-first (Cargo, npm, pip) — Mo commits to this from v0.
- H2 Standard-library-first (Go, Java) — Mo aims for a rich, capability-declared stdlib.
- **H4 SemVer + backward compatibility** — a discipline, not a hope.
- H6 Documentation as first-class (Rust, Elixir) — culture from day one.
- **H8 Package security and supply-chain defense** — Mo's differentiator; see [[d30-supply-chain-security]], [[q17-package-management-and-supply-chain]], [[supply-chain-defenses]].

## The cross-cutting trade-offs

The report closes with ten tension pairs. Mo's stated positions:

- **Expressiveness vs. simplicity** — pick simplicity; agents don't need to "be clever."
- **Safety vs. performance** — safety wins by default; escape hatches are capability-guarded.
- **Compile-time vs. runtime cost** — compile-time wins; agent inner loops need fast iteration but also fast rebuild.
- **Author cost vs. reader cost** — reader cost wins. Agents author; humans read.
- **AI vs. human authoring** — first-class AI authoring is not a compromise; it's the primary design constraint.
- **Innovation vs. familiarity** — familiarity wins for surface syntax; innovation lives in semantics.
- **Small language + big library vs. big language + small library** — small language, big library.
- **Backward compatibility vs. progress** — Rust's epoch model wins.
- **Package ecosystem security vs. ecosystem growth** — security wins. Slower growth is acceptable.

## The point

The eight camps are not a menu of exclusive choices. They are dimensions on which every language takes a position — often unconsciously. The value of the map is that it forces the designer to make each position explicit, cite the exemplars they are drawing from, and name the trade-off they are accepting.

Mo's positions on all eight are captured in the [[plang-decision-matrix]] and [[plang-mo-synthesis]] pages.

## Sources

- [Full report](../raw/plang-history-2026-09/camps/design_camps_and_tradeoffs.md)
- [Van Roy, "Programming Paradigms for Dummies"](https://webperso.info.ucl.ac.be/~pvr/VanRoyChapter.pdf)
- [Hickey, "Simple Made Easy"](https://github.com/matthiasn/talk-transcripts/blob/master/Hickey_Rich/SimpleMadeEasy-mostly-text.md)
- [Kay, "The Early History of Smalltalk"](https://www.cs.tufts.edu/comp/150FP/archive/alan-kay/smalltalk-hopl-ii.pdf)
- [Stroustrup, HOPL IV C++ paper](https://www.stroustrup.com/hopl20main-p5-p-bfc9cd4--final.pdf)


## Related

- [[plang-implementation-menu]]
- [[plang-mo-synthesis]]
- [[plang-decision-matrix]]
- [[language-landscape]]
- [[case-against-new-languages]]
