# Dependent Types — Lean, Idris, and Agda

This deep-dive covers three languages that pushed *dependent types* from a theoretical curiosity into working tools for mathematicians and programmers: **Agda**, **Idris**, and **Lean**. Each descends from the same lineage — Martin-Löf type theory, the Curry–Howard correspondence, and the ML tradition — yet each stakes out a different corner of the design space.

## Origin story

### Designers, institutions, years

**Agda.** Originally developed by **Ulf Norell** at **Chalmers University of Technology**; the current implementation (Agda 2) is a full rewrite described in Norell's PhD thesis. "First appeared: 1.0 – 1999; 2.0 – 2007." Version 1.0 was designed by Catarina Coquand ([Wikipedia: Agda](https://en.wikipedia.org/wiki/Agda_(programming_language))). A short overview paper appeared as "A Brief Overview of Agda — A Functional Language with Dependent Types" (2009) ([Chalmers publication 103342](https://research.chalmers.se/en/publication/103342)).

**Idris.** Designed by **Edwin Brady**. "First appeared: 2007." Named after "a singing dragon from the 1970s UK children's television programme *Ivor the Engine*." Influences: "Agda, Clean, Rocq (previously known as Coq), Epigram, F#, Haskell, ML, Rust" ([Wikipedia: Idris](https://en.wikipedia.org/wiki/Idris_(programming_language))). **Idris 2** — the current self-hosted implementation — is described in Brady's ECOOP 2021 paper "Idris 2: Quantitative Type Theory in Practice" ([arXiv 2104.00480](https://arxiv.org/abs/2104.00480)).

**Lean.** Designed by **Leonardo de Moura**, developed at **Microsoft Research**, later at **Amazon Web Services**. "Lean was launched in **2013**." "Lean 3 was first released on **January 20, 2017**, and was the first moderately stable version of Lean. It was implemented primarily in C++, with some features written in Lean itself." "Lean 4 was released as a reimplementation of the Lean theorem prover" in **2021**. Governance moved to the nonprofit **Lean Focused Research Organization (Lean FRO)** in **2023** ([Wikipedia: Lean](https://en.wikipedia.org/wiki/Lean_(proof_assistant))). The Lean 4 design paper is Leonardo de Moura and Sebastian Ullrich, ["The Lean 4 Theorem Prover and Programming Language"](https://lean-lang.org/papers/lean4.pdf).

### Motivating problems

The three projects share an ancestor — **Martin-Löf type theory** (1970s) — and its embodiment in the **Curry–Howard correspondence**: types are propositions, programs are proofs. But each project's motivations differed:

- **Agda** — a research vehicle for dependent types as a *programming* language, following the older **ALF** system at Chalmers. Norell's PhD thesis rebuilt Agda from scratch with the goal of making dependent types practical to type-check and interact with.
- **Idris** — a *general-purpose* dependently typed language "similar to Haskell," designed for programming with dependent types, not primarily as a proof assistant. Brady's later work targeted **linear + dependent types** through Quantitative Type Theory (QTT).
- **Lean** — a *proof assistant* with an efficient functional core. Lean 4's paper explicitly frames it as "both an extensible theorem prover" and "an efficient functional programming language" ([Lean 4 paper](https://lean-lang.org/papers/lean4.pdf)).

### Initial reception

Agda drew academic users and became a teaching language at Chalmers, Edinburgh, Nottingham. Idris built a small but devoted community drawn from the Haskell world. Lean grew slowly through Lean 2 and 3, then exploded through **mathlib** — a community mathematics library — after Kevin Buzzard began evangelising it to mathematicians around 2017.

## Design philosophy

### Common core principles

- **Types depend on values.** From Idris: "With dependent types, values can appear in types." An idiomatic example: `Vect : Nat -> Type -> Type` — a length-indexed vector ([Wikipedia: Idris](https://en.wikipedia.org/wiki/Idris_(programming_language))).
- **Totality matters.** A non-terminating "proof" can prove anything, so total functions and structural recursion checks are central. "Agda is a total functional programming language: Every program must terminate. All possible patterns must be matched. Without termination and complete pattern matching, the logic behind the language would become inconsistent and arbitrary statements could be proved" ([Wikipedia: Agda](https://en.wikipedia.org/wiki/Agda_(programming_language))).
- **Small trusted kernel.** All three keep the core type checker small so the trusted computing base is auditable.
- **Interactive elaboration.** Programs and proofs are constructed with holes (metavariables) that the elaborator can fill in.

### What each language rejected

- **Agda** — no separate tactic language: "Unlike Rocq, Agda has no separate tactics language; proofs are written in a functional programming style" ([Wikipedia: Agda](https://en.wikipedia.org/wiki/Agda_(programming_language))). Agda instead uses **dependently typed pattern matching** as a primitive.
- **Idris** — rejected pure academic focus in favor of usability as a general-purpose language. Idris 2 additionally rejected the old core in favor of **QTT**.
- **Lean** — Lean 4 explicitly rejected Lean 3's limitations: "Users could not modify many parts of the system without changing Lean 3 source code written in C++"; "many proof automation metaprograms were not competitive with automation implemented in C++ and OCaml"; "the primary source of inefficiency in Lean 3 metaprograms was virtual-machine interpretation overhead" ([Lean 4 paper](https://lean-lang.org/papers/lean4.pdf)). Lean 4 was rewritten in Lean itself and compiles to C.

### Cultural values

- **Agda** — academic, Haskell-adjacent, Emacs-native.
- **Idris** — pragmatic programming with proofs; small dedicated community.
- **Lean** — increasingly the choice of working mathematicians; mathlib culture emphasizes collaboration, style, and continuous integration.

## Language features

### Syntax

**Agda:** Haskell-like, mixfix operators built into the language (underscores mark argument positions), Unicode identifiers routine:

```agda
data _≤_ : ℕ → ℕ → Set where
  z≤n : {n : ℕ} → zero ≤ n
  s≤s : {n m : ℕ} → n ≤ m → suc n ≤ suc m
```

([Wikipedia: Agda](https://en.wikipedia.org/wiki/Agda_(programming_language)))

**Idris:** Haskell-like:

```idris
data Vect : Nat -> Type -> Type where
  Nil : Vect 0 a
  (::) : (x : a) -> (xs : Vect n a) -> Vect (n + 1) a

total
append : Vect n a -> Vect m a -> Vect (n + m) a
append Nil ys = ys
append (x :: xs) ys = x :: append xs ys
```

([Wikipedia: Idris](https://en.wikipedia.org/wiki/Idris_(programming_language)))

**Lean 4:** Its own syntax, with a highly extensible parser. Lean 4 provides "a hygienic macro system custom-built for interactive theorem provers" ([Lean 4 paper](https://lean-lang.org/papers/lean4.pdf)). Notation and macros are user-extensible via `syntax`, `macro`, and `macro_rules`; the Lean 3 `notation` keyword itself is now a macro.

### Type system

**Agda.** "Strong, static, dependent, nominal, manifest, inferred." Based on "Zhaohui Luo's unified theory of dependent types (UTT), a type theory similar to Martin-Löf type theory." Supports "inductive data types" as the main way of defining data ([Wikipedia: Agda](https://en.wikipedia.org/wiki/Agda_(programming_language))).

**Idris.** Dependent; Idris 2's core is **Quantitative Type Theory (QTT)**: "Recent work on Quantitative Type Theory (QTT) extends dependent type systems with linearity, also allowing precision in expressing when a function can run" ([arXiv 2104.00480](https://arxiv.org/abs/2104.00480)). Practical benefits include "expressing which data is erased at run time, at the type level" and "resource tracking in the type system leading to type-safe concurrent programming with session types." QTT annotates every variable with a *quantity* — 0 (erased), 1 (linear/used once), or ω (unrestricted).

**Lean.** "Strict purely functional, dependently typed." Foundation: "Calculus of constructions with inductive types, specifically the Calculus of Inductive Constructions." Typing discipline: "Static, strong, inferred" ([Wikipedia: Lean](https://en.wikipedia.org/wiki/Lean_(proof_assistant))).

### Memory model

All three are automatic-memory-managed. **Lean 4** uses **reference counting** with in-place update optimisations — a distinctive design choice for a functional language. The paper attributes the runtime's efficiency partly to compile-time reuse of unique references. **Agda** and **Idris** rely on their backend runtimes (GHC/JavaScript for Agda; Scheme/C for Idris 2).

### Concurrency

Not central to any of the three. **Idris 2**'s session-types work uses QTT's linearity to check communication protocols at compile time ([arXiv 2104.00480](https://arxiv.org/abs/2104.00480)). Lean 4 offers standard concurrency primitives in its `Std` library, "including tree maps, hash maps, datetime functions, and concurrency primitives" ([Wikipedia: Lean](https://en.wikipedia.org/wiki/Lean_(proof_assistant))).

### Error handling

Pure functional style — `Maybe`/`Option`, `Either`/`Except`, and monadic effects. All three encourage using the type system so that many errors are impossible by construction.

### Metaprogramming

**Agda.** Reflection lets "program fragments be quoted into, or unquoted from, the abstract syntax tree. Agda's reflection mechanism is used similarly to Template Haskell." Proof-search plugin in Emacs mode "enumerates possible proof terms" and "is limited to 5 seconds" ([Wikipedia: Agda](https://en.wikipedia.org/wiki/Agda_(programming_language))).

**Idris.** Tactic-based interaction "in the style of Rocq" plus "interactive elaboration of proof terms, in the style of Epigram and Agda" ([Wikipedia: Idris](https://en.wikipedia.org/wiki/Idris_(programming_language))).

**Lean 4.** Metaprogramming is a headline feature. "Lean 4 is intended to be fully extensible. Users can modify and extend: the parser, the elaborator, tactics, decision procedures, the pretty printer, the code generator" ([Lean 4 paper](https://lean-lang.org/papers/lean4.pdf)). Macros are hygienic; the `macro` command itself is a command-level macro; `macro_rules` allow extending existing macros. Users "can implement efficient proof automation in Lean, compile it into efficient C code, and load it as a plugin."

### Module system

Standard hierarchical modules in all three. Lean 4 supports namespaces, sections, and `open` imports; Idris and Agda use record and namespace mechanisms familiar from ML/Haskell.

### Notable innovations

- **Agda:** dependently typed pattern matching as a language primitive; unicode-heavy mixfix syntax.
- **Idris 2:** QTT — the first mainstream dependently typed language integrating linear types at the core.
- **Lean 4:** self-hosted with C-compiled tactics; a hygienic macro system built for a theorem prover; a rich extensibility surface for the elaborator and parser.

## Implementation

### Reference compilers

- **Agda 2:** implemented in Haskell; type-checks and compiles to GHC-backed executables (or JavaScript).
- **Idris 2:** self-hosted in Idris; compiles to Scheme (Chez by default) or C ([Wikipedia: Idris](https://en.wikipedia.org/wiki/Idris_(programming_language))).
- **Lean 4:** self-hosted in Lean; frontend and elaborator are Lean; kernel and low-level runtime are C++. "Lean 4 allows users to modify the frontend and other key parts of the core system without touching C++ code, because these parts are implemented in Lean and can be overridden by the end user"; Lean 4 uses "the C++17 version of C++" ([Wikipedia: Lean](https://en.wikipedia.org/wiki/Lean_(proof_assistant))).

### Elaboration and IR

Elaboration is where dependently typed languages spend most compile time — inferring implicit arguments, unifying types, solving typeclass problems. Lean 4 exposes elaboration hooks so users can intercept and modify it. Agda's interactive Emacs mode is essentially a UI over elaboration.

### Backends

- **Agda** → Haskell (GHC), JavaScript, others via compiler backends.
- **Idris 2** → Chez Scheme, Racket, JavaScript (browser and Node), C ([Wikipedia: Idris](https://en.wikipedia.org/wiki/Idris_(programming_language))).
- **Lean 4** → C. Lean 4 "can produce C code that is then compiled, enabling efficient domain-specific automation" ([Wikipedia: Lean](https://en.wikipedia.org/wiki/Lean_(proof_assistant))). This is what makes Lean-authored tactics competitive with C++/OCaml implementations elsewhere.

### Runtime and GC

- **Agda:** GHC runtime for the Haskell backend.
- **Idris 2:** Scheme runtime by default; a C runtime is also supported.
- **Lean 4:** custom runtime with reference counting.

### Bootstrapping

All three have gone through the classic bootstrap arc. Idris 2 and Lean 4 are both self-hosted; Agda's implementation remains in Haskell.

### Alternative implementations

Small research implementations exist (e.g., partial Agda reimplementations); the reference implementations dominate.

## Ecosystem

### Package managers

- **Agda:** cabal/GHC ecosystem for host tooling; a lightweight `libraries` mechanism for Agda modules.
- **Idris 2:** `pack` package manager.
- **Lean 4:** `lake` — build tool and package manager written in Lean.

### Standard libraries

- **Agda:** "Agda has an extensive de facto standard library containing definitions and theorems about basic data structures, including: natural numbers, lists, vectors. The standard library is in beta and under active development" ([Wikipedia: Agda](https://en.wikipedia.org/wiki/Agda_(programming_language))).
- **Idris 2:** ships a base library and prelude; smaller than Lean's or Agda's.
- **Lean 4:** "The official Lean standard library is called *Std*. *Std* contents: Common data structures and functions, including tree maps, hash maps, datetime functions, and concurrency primitives" ([Wikipedia: Lean](https://en.wikipedia.org/wiki/Lean_(proof_assistant))). A community library called *batteries* provides additional structures.

### Tooling

- **Agda:** deeply integrated **Emacs mode**; also Atom and VS Code plugins. Batch mode via CLI.
- **Idris 2:** Emacs, VS Code, Vim; REPL-driven development is core.
- **Lean 4:** "Visual Studio Code, Neovim, and Emacs. Editor communication: Client extension and Language Server Protocol server" ([Wikipedia: Lean](https://en.wikipedia.org/wiki/Lean_(proof_assistant))). VS Code integration (with the *lean4-mode* extension) is the mainstream experience.

### Community and governance

- **Agda:** academic community at Chalmers, Edinburgh, Strathclyde, Nottingham.
- **Idris:** Edwin Brady leads; funded partly by St Andrews and community contributions.
- **Lean:** governed by the **Lean FRO** (formed 2023), whose goals include "improving the language's scalability and usability and implementing proof automation" ([Wikipedia: Lean](https://en.wikipedia.org/wiki/Lean_(proof_assistant))). Corporate backing from AWS via de Moura.

### Mathlib — the mathematics library that made Lean famous

**mathlib** is Lean's community mathematics library. "The community started the Lean mathematical library project mathlib" in 2017 in Lean 3 ([Lean 4 paper](https://lean-lang.org/papers/lean4.pdf)). It has since migrated to Lean 4.

Current mathlib4 stats:
- **34,725 commits**, **4.1k stars**, **1.7k forks**, **786 contributors**
- Latest release **v4.33.1**, released **August 21, 2026**
- **Languages:** Lean 99.7%
- Maintained across dozens of areas: "Algebra, Number theory, Tactics, Algebraic geometry, Category theory, Lean formalization, Type theory, Proof engineering, Documentation, Infrastructure, Topology, Functional analysis, Calculus, Probability, Measure theory, Analysis, Model theory, Linear algebra, Geometry, Operator algebras, Combinatorics, Metaprogramming, Homology, Differential geometry, Linters" ([mathlib4 on GitHub](https://github.com/leanprover-community/mathlib4)).

"As of May 2025, mathlib had formalized over **210,000 theorems**, **100,000 definitions**. In 2026, mathlib was awarded the **Demailly prize for open science**" ([Wikipedia: Lean](https://en.wikipedia.org/wiki/Lean_(proof_assistant))).

## Adoption

### Users

- **Agda:** primarily academic — courses on type theory, dependent types, and proof at Chalmers, Nottingham, Edinburgh; some industrial research use.
- **Idris:** Haskellers exploring dependent types; embedded DSL builders; academic and hobbyist use.
- **Lean:** exploding among **research mathematicians** — Peter Scholze's Liquid Tensor Experiment (formalized in Lean 3, ported to Lean 4) is the emblematic success story. The 2025 SIGPLAN award citation credited "significant impact on mathematics, hardware and software verification, and AI" ([Wikipedia: Lean](https://en.wikipedia.org/wiki/Lean_(proof_assistant))).

### Where each dominates

- **Agda** — teaching type theory; small research artifacts; total functional programming.
- **Idris** — showcasing QTT and dependently typed programming; small production experiments; embedded DSLs.
- **Lean** — formalized mathematics (mathlib); increasing use in AI-assisted theorem proving; verification of AWS services (via de Moura's group).

### Where they failed to spread

- **Agda:** never built a strong industrial user base; ecosystem remains small; tooling outside Emacs is limited.
- **Idris:** growth capped by small ecosystem and the general challenge of making dependently typed programming productive.
- **Lean:** production programming beyond proofs is not the main use case; Lean 4 targets both, but the community centre of gravity is mathematics.

### Momentum (2026)

- **Lean:** the strongest of the three by far. FRO staff, corporate backing, the mathlib flywheel, the mathematics community, and heavy use as a target for AI theorem proving (autoformalization, tactic prediction). "The ACM SIGPLAN Programming Languages Software Award was awarded to Gabriel Ebner, Soonho Kong, Leo de Moura, and Sebastian Ullrich for Lean" in 2025. In 2026 mathlib was awarded the **Demailly prize** ([Wikipedia: Lean](https://en.wikipedia.org/wiki/Lean_(proof_assistant))).
- **Idris 2:** steady. Latest release: **v0.8.0**, released **October 31, 2025** ([Wikipedia: Idris](https://en.wikipedia.org/wiki/Idris_(programming_language))). Development continues under Edwin Brady with community contributions.
- **Agda:** steady, primarily academic. Stable release **2.8.0 / July 5, 2025** ([Wikipedia: Agda](https://en.wikipedia.org/wiki/Agda_(programming_language))).

## Criticism and open problems

- **Compile-time performance.** Elaboration and typeclass resolution can be slow. Lean 4 explicitly targets improvements: "Typeclass resolution could have exponential running times in the presence of diamonds" ([Lean 4 paper](https://lean-lang.org/papers/lean4.pdf)).
- **Learning curve.** Dependent types demand type-theory intuition rare among practising programmers.
- **Ecosystem size.** All three ecosystems are dwarfed by Haskell/OCaml, let alone mainstream languages.
- **Documentation and tooling.** Improving but still uneven; Lean 4's tooling is now the strongest of the three.
- **Termination checking and universe polymorphism** trip up newcomers.
- **Mathlib migration** (Lean 3 → Lean 4) was a multi-year, community-wide effort — a lesson in the costs of a non-backwards-compatible major version.
- **Agda's proof search:** limited to a hard 5-second cap in Emacs mode ([Wikipedia: Agda](https://en.wikipedia.org/wiki/Agda_(programming_language))).
- **Idris 2's tactic library** is "not yet as useful as Rocq's" ([Wikipedia: Idris](https://en.wikipedia.org/wiki/Idris_(programming_language))).

## Influence on other languages

- **Rocq (formerly Coq)** and Lean sit alongside each other as the mainstream proof assistants; each borrows ideas from the other.
- **F\*** (Microsoft Research) and **Dafny** — verification-oriented languages influenced by dependent-type research.
- **Idris** and **QTT** — inspired ongoing research on integrating linear and dependent types in Rust-like languages.
- **Rust's type system**, though not dependently typed, borrows heavily from the linear/affine tradition Idris 2 also draws on. Idris's own influence list explicitly includes **Rust** ([Wikipedia: Idris](https://en.wikipedia.org/wiki/Idris_(programming_language))).
- **Agda** shaped the design of GHC's more advanced type-system extensions (e.g., type families, dependent Haskell proposals).
- **Lean 4's metaprogramming** — hygienic macros over syntax quotations — is influencing new languages designed for extensibility.
- **Lean 4 as an AI target.** LLM-based mathematics assistants (e.g., DeepMind's AlphaProof, Terence Tao's Lean-assisted work) rely on Lean's efficient runtime and formal foundations.

## Key sources

**Lean:**
- Leonardo de Moura and Sebastian Ullrich, ["The Lean 4 Theorem Prover and Programming Language"](https://lean-lang.org/papers/lean4.pdf).
- ["Lean (proof assistant)" on Wikipedia](https://en.wikipedia.org/wiki/Lean_(proof_assistant)).
- [leanprover-community/mathlib4 on GitHub](https://github.com/leanprover-community/mathlib4).
- Lean FRO — [lean-fro.org](https://lean-fro.org).
- Lean project site — [lean-lang.org](https://lean-lang.org).

**Idris:**
- Edwin Brady, ["Idris 2: Quantitative Type Theory in Practice"](https://arxiv.org/abs/2104.00480), ECOOP 2021.
- ["Idris (programming language)" on Wikipedia](https://en.wikipedia.org/wiki/Idris_(programming_language)).
- [Idris 2 documentation](https://idris2.readthedocs.io/en/latest/tutorial/conclusions.html).

**Agda:**
- Ulf Norell, ["A Brief Overview of Agda — A Functional Language with Dependent Types"](https://research.chalmers.se/en/publication/103342), Chalmers, 2009.
- ["Agda (programming language)" on Wikipedia](https://en.wikipedia.org/wiki/Agda_(programming_language)).
- Ulf Norell, "Towards a Practical Programming Language Based on Dependent Type Theory," PhD thesis, Chalmers, 2007.

**Background:**
- Per Martin-Löf, "Intuitionistic Type Theory" (1984).
- Zhaohui Luo, "Computation and Reasoning: A Type Theory for Computer Science" (1994).
- Robert Harper, "Practical Foundations for Programming Languages" — background on type theory as it applies to language design.
