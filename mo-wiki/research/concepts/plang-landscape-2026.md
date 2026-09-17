---
title: "Programming language landscape as of 2026"
created: 2026-09-13
updated: 2026-09-17
type: concept
tags: [research, history]
sources:
  - "../../raw/plang-history-2026-09/history/03_2010_to_2026.md"
  - "../../raw/plang-history-2026-09/synthesis/executive_summary.md"
contested: true
contradictions: [01-premise, d24-compile-to-c-via-zig, q13-implementation-language]
---
# Programming language landscape as of 2026

> **17 Sep 2026.** This page is the 13 Sep synthesis of an external research run. The Mo it describes — brace syntax, effect rows, a Rust implementation, a package registry, an RFC process — was never Mo's design. Mo's decisions are the spec chapters under `spec/design-v0/` and the [[decision-log]]. Read this page as landscape only.

## Headline

A 2026-vintage read of where mainstream programming languages actually are — after the systems-safety wave (Rust), the effect-typing wave (Koka/OCaml 5), the machine-verification wave (Verus/Dafny), and the first real AI-authorship wave. This page complements [[language-landscape]] (which lists every language considered for Mo's steal-list) by mapping the *positions* those languages now occupy relative to each other and to Mo's design bets.

## How this differs from [[language-landscape]]

- [[language-landscape]] catalogs individual languages with "the one idea worth stealing" for each. It is a *steal-list*.
- This page maps the current field as a *landscape*, grouping languages by the design axis they contest. Use this to reason about *positioning*: where the field converges, where it splits, and where Mo has room to differentiate.
- Both feed [[plang-mo-synthesis]] and [[plang-decision-matrix]]; this one is the birds-eye view.

## Five convergences by 2026

1. **Every serious systems language ships a canonical formatter and JSON diagnostics.** `gofmt`, `rustfmt`, `zig fmt`, `mo fmt`. LLM autofix loops make this the new competitive floor. See [[q06-verified-line]].
2. **Structured concurrency is winning.** Trio (Python), Swift 6, Kotlin coroutines, [JEP 505 (Java structured concurrency)](https://openjdk.org/jeps/505), Erlang supervision trees, Go's `errgroup`. Every modern async story is converging on parent-scoped task lifetimes. [[d12-concurrency-at-the-edges]]
3. **Algebraic effects have graduated from research.** Koka, OCaml 5's effect handlers, Unison's abilities, Effekt's lexical handlers. Ten years ago effects were a papers-only feature; now they ship in mainstream compilers. [[d15-effects-via-capabilities]]
4. **Supply-chain security is table stakes.** SLSA levels, Sigstore, PyPI trusted publishers, Cargo OIDC discussions, npm provenance attestations, GitHub Actions attestations. No new language will be taken seriously without a supply-chain story. [[d30-supply-chain-security]] · [[supply-chain-defenses]]
5. **LLM authorship is a first-class design consideration.** Grammar-constrained decoding ([Outlines](https://dottxt-ai.github.io/outlines/), [XGrammar](https://blog.mlc.ai/2024/11/22/achieving-flexible-portable-structured-generation-with-xgrammar), [SynCode](https://arxiv.org/abs/2403.01632)) makes LL(1)/LALR(1) grammars measurably more valuable than they were in 2020. [[q06-verified-line]]

## Four splits still contested

1. **Memory model** — GC (Go, JVM, .NET) vs ownership+borrowing (Rust) vs regions (Cyclone/MLKit/Vale) vs generational references (Vale) vs mutable value semantics (Hylo). Mo sits with regions + affine handles.
2. **Type-system foundation** — Global HM inference (OCaml/Haskell) vs bidirectional System F (Rust/Swift) vs refinement types (Verus/Dafny/F*) vs dependent types (Idris/Lean 4). Mo composes bidirectional + refinement + effects + capabilities.
3. **Effect discipline** — Implicit/ambient (Go, Python, JS) vs monadic (Haskell) vs algebraic handlers (Koka, OCaml 5) vs capabilities-as-authority (Austral, Wyvern, Pony) vs "capabilities give effects for free" (Craig et al.). Mo does effect rows + capability parameters.
4. **Compilation strategy** — LLVM (Rust, Swift, Julia, Zig) vs Cranelift (Wasmtime) vs custom VMs (BEAM, Lua, CPython) vs C-transpilation (Nim). Mo stages custom VM → Cranelift → LLVM → Wasm.

## Notable 2020–2026 arrivals and inflection points

- **Rust editions (2021, 2024)** demonstrated that per-crate breaking changes can happen without ecosystem trauma. See [Rust editions guide](https://doc.rust-lang.org/edition-guide/). Every new language that doesn't ship an edition mechanism from day one will regret it.
- **OCaml 5 effect handlers (2022)** made algebraic effects production-mainstream. See [OCaml 5 effects manual](https://ocaml.org/manual/5.3/effects.html) and the [Multicore OCaml paper](https://kcsrk.info/papers/system_effects_feb_18.pdf).
- **Verus (2023)** — Rust plus SMT-checked refinement types, the first mainstream statement that agent-payable annotation cost changes the design math. See [Verus paper](https://arxiv.org/abs/2303.05491).
- **Roc's platforms (evolving through 2024–2026)** cleanly separated pure language from effectful runtime. Also the first mainstream Zig-implemented compiler with incremental rebuilds measured in tens of milliseconds — 35 ms, but only on a Zig nightly on x86-64; stable was 8.6 s (qualifier added 17 Sep 2026, from [[roc]]). See [Roc "Fast"](https://www.roc-lang.org/fast).
- **Unison 1.0 (Nov 2025)** shipped content-addressed code as a general-purpose language. Every function is identified by the hash of its normalized AST; renames don't break references. See [Unison big idea](https://www.unison-lang.org/learn/the-big-idea/).
- **Gleam** — evidence that a typed BEAM has a real audience. 2nd most-admired language in Stack Overflow's 2025 survey.
- **Elixir 1.20 (Jun 2026)** — gradually typed with full inference and no annotations, reporting "verified bugs" with very low false positives.
- **TypeScript rewrite to Go (2025)** — the mainstream language whose compiler was itself a mainstream language got rewritten for compile-speed reasons. Concrete evidence that compile-time-cost decisions never stop mattering.
- **Mojo (evolving 2023–2026)** — MLIR-first, Python-syntax-inspired, aimed at AI accelerators. First real evidence that "AI-era language" doesn't necessarily mean "language for authors that are AIs" — Mojo's premise is "language for hardware that runs AI."
- **Ada 2022 / SPARK 2025** — the 2025 Marmaragan study proposed an LLM-in-the-loop workflow where humans write high-level contracts and the LLM proposes lower-level annotations that SPARK's prover checks. First concrete demonstration of Mo's central bet, at benchmark scale (36 of 71 cases, 50.7%) rather than production scale (corrected 17 Sep 2026).

## Where Mo differentiates

The Mo bet is that *coherence across all layers* is the scarcest resource in language design, and that agent authorship makes coherence affordable in a way it wasn't before. Concretely, Mo places itself at the intersection where:

- **Type system**: bidirectional System F + refinements + effects + capabilities. No other production language ships this combination.
- **Memory**: regions primary, affine handles on external resources. Rust-adjacent safety without lifetime parameters. Learning cliff much lower than Rust.
- **Concurrency**: structured concurrency over algebraic effect handlers. Cancellation, retry, timeouts, and errors all handled by the same primitive.
- **Package system**: capability-declared manifests + content-addressed identity + release-age gates + Sigstore/OIDC signing + declarative-only build scripts. Stricter than any production ecosystem by design.
- **Tooling**: `mo fmt`, `mo build`, `mo test`, `mo doc`, `mo publish` shipped in one binary from day one. Go's model.

No existing language is a subset of this stack — Rust lacks refinements, capabilities, and the manifest security story; Roc lacks refinements and imperative regions; Austral lacks effects and the ecosystem; Verus is Rust + verification but retains Rust's other choices; Koka lacks the memory model and package system. Mo's positioning is the *union* of the strongest recent moves.

## What the landscape says about launch strategy

- **Pick a first workload.** Rust had Servo. Elixir had WhatsApp-scale messaging. Go had Google infrastructure. Julia had scientific computing. Mo's natural fit is *AI-agent tooling itself* — compilers, analyzers, MCP servers, evaluators — where the annotation-heavy contract style buys the most.
- **Ship the toolchain in one binary, from day one.** No exceptions since Go established the pattern.
- **Structured JSON diagnostics from day one.** LLM autofix loops require them; without them Mo's design premise is compromised.
- **A first-class book.** *The Rust Programming Language*, *Programming Elixir*, *Programming in Lua* — every mature ecosystem has one.
- **RFC discipline from pre-1.0.** Not for consensus building at this stage — for documenting rationale for future contributors.

See [[plang-history-2010-to-2026]] for the underlying decade-by-decade view of how this landscape formed, and [[case-against-new-languages]] for the counterargument.

## Sources

- [History 2010–2026](../../raw/plang-history-2026-09/history/03_2010_to_2026.md)
- [Executive summary](../../raw/plang-history-2026-09/synthesis/executive_summary.md)
- [Rust editions guide](https://doc.rust-lang.org/edition-guide/)
- [OCaml 5 effects manual](https://ocaml.org/manual/5.3/effects.html)
- [Verus arXiv paper](https://arxiv.org/abs/2303.05491)
- [Roc "Fast"](https://www.roc-lang.org/fast)
- [Unison big idea](https://www.unison-lang.org/learn/the-big-idea/)
- [JEP 505 — structured concurrency](https://openjdk.org/jeps/505)
- [SLSA specification](https://slsa.dev/spec/v1.0/levels)


## Related

- [[language-landscape]] — the steal-list, one-idea-per-language
- [[landscape-second-lane]]
- [[case-against-new-languages]]
- [[comparison-synthesis-draft]]
- [[capability-module-lineage]]
- [[supply-chain-defenses]]
- [[plang-history-2010-to-2026]]
- [[plang-mo-synthesis]]
- [[plang-decision-matrix]]
