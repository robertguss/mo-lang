---
title: "PL history: 2010 through September 2026"
created: 2026-09-13
updated: 2026-09-13
type: deep-dive
tags: [history, modern, ai-era]
sources:
  - "../raw/plang-history-2026-09/history/03_2010_to_2026.md"
---

### Headline

Sixteen years in which language design collapsed the false trade-offs of the 1990s. Memory safety without a GC (Rust). Type inference without dynamism (Julia, TypeScript). Package managers bundled from day one (Cargo). Then the AI turn (2023+) rewrote who the language is *for*.

### Three findings that shape everything

- **Cargo (2014) is the design template.** A first-class package manager with a lockfile, `SemVer` resolution, workspaces, and features — shipped with Rust from 1.0. Every language since has copied it or paid the price for not doing so.
- **MVS (Russ Cox, 2018) is the sane alternative to SAT resolvers.** Go modules pick the *minimum* version satisfying all constraints. Reproducibility by construction; no lock file needed for correctness. Slower to get new features, but no surprise builds.
- **The AI turn (2023–2026) makes an LLM the principal user of the language.** Grammar-constrained decoding (PICARD, Outlines, XGrammar), Model Context Protocol (Anthropic, Nov 2024), and slopsquatting attacks reshape what the language must optimize for. See [[d01-agents-write-the-code]].

### Era 7: The 2010s — systems renaissance & type-system maturity

**Systems languages.**

- **Go** (Griesemer/Pike/Thompson, 2009, 1.0 in 2012) — deliberate simplicity, goroutines/channels, `gofmt` culture, and eventually MVS. See [[go-history]].
- **Rust** (Hoare + Mozilla, 1.0 May 2015) — ownership + borrow checking + traits + Cargo. See [[rust]].

**Modern JVM/ecosystem languages.**

- **Kotlin** (JetBrains, 2011; Android first-class 2017) — practical Java replacement.
- **Swift** (Lattner + Apple, 2014; open-sourced 2015) — the Objective-C successor.
- **Elixir** (Valim, 2011) — Ruby-flavored Erlang on BEAM. See [[elixir]].
- **Julia** (Bezanson et al., MIT; 1.0 2018) — dynamic-typed with type inference; scientific computing.

**Web/JS ecosystem.**

- **TypeScript** (Hejlsberg + Microsoft, October 2012) — gradual types on top of JS. Won the industry.
- **Dart + Flutter** (Google, 2011 / Flutter era 2018+) — mobile cross-platform.
- **Elm** (Czaplicki, 2012) — pure functional web; friendly errors.

**Dependent types go practical.**

- **Idris 2** (Brady, ECOOP 2021) — Quantitative Type Theory (linear + dependent).
- **Lean 4** (de Moura, 2021; **mathlib** community) — proof assistant and functional PL. See [[dependent-types]].
- **Rocq** (formerly Coq, renamed 2024).

### Era 8: Late 2010s–early 2020s — verification, effects, capabilities

- **Zig** (Kelley, 2016+) — "more pragmatic than C." See [[zig]].
- **Koka** (Leijen, Microsoft Research) — algebraic effects with evidence-passing translation.
- **OCaml 5.0** (December 2022) — first mainstream shipping language with effect handlers as a runtime feature.
- **Unison** (Chiusano, Bjarnason) — content-addressed code; every function has a hash-based name. Ancestry: Nix derivations. See [[unison]].
- **Roc** (Feldman, 2019+) — pure functional; Elm-inspired; capability-aware effects. See [[roc]].
- **Gleam** (Pilfold, 2016+, 1.0 March 2024) — statically typed BEAM language.
- **Austral** (Borretti, 2018+) — linear types + capabilities + no `null`. Explicit inspiration for Mo. See [[austral]].
- **Vale** (Ovadia, 2019+) — generational references for memory safety without GC or borrow checker.
- **Hylo** (formerly Val; Racordon, 2022+) — mutable value semantics; subscripts and parts. See [[hylo]].
- **Carbon** (Google, 2022+) — a C++ successor for organizations that cannot leave the ecosystem.
- **Mojo** (Modular / Lattner, 2023+) — Python-superset for AI/ML kernels; MLIR-first.

### Era 9: The AI era, 2023–2026

- **Grammar-constrained decoding.** PICARD (EMNLP 2021), Outlines (2023), XGrammar (2024), Guidance, SynCode. LLMs can now be forced to emit syntactically valid programs in any CFG.
- **Copilot (2021) → Cursor (2023) → agentic coding (2024+).** By 2026 a large fraction of production code is agent-generated.
- **Model Context Protocol** (Anthropic, November 2024) — standardizes how LLMs discover and invoke tools.
- **Slopsquatting** — attackers register packages LLMs hallucinate. See [Cloud Security Alliance report](https://cloudsecurityalliance.org/blog/2025/06/03/what-is-slopsquatting-how-ai-hallucinations-are-fueling-a-new-class-of-supply-chain-attacks). Direct motivation for [[d30-supply-chain-security]].
- **Verification renaissance.** Prusti, Verus, Creusot, Aeneas, Flowistry all put Rust-adjacent verification within reach of production engineers.
- **Effect systems in production.** OCaml 5, Unison, Roc, Koka — algebraic effects with handlers.
- **Capability revival.** Austral, Monte, Object-Capability lineage all resurfacing.
- **Content-addressed code.** Unison, plus Nix derivations, plus emerging build-cache designs.
- **WebAssembly maturation.** WASI Preview 2 (2024), component model landing, WebAssembly as a portable systems target.

### Cross-cutting themes

- **Compiler infrastructure.** LLVM, MLIR, Cranelift, GCC — every new language starts by picking one.
- **Package-manager evolution.** Cargo → npm's ecosystem gravity → PubGrub (Dart, uv) vs. MVS (Go) vs. SAT (npm, Cargo).
- **LSP + tree-sitter.** Editor integration ships within months, not years, for any new language.
- **Format + lint tooling standardization.** `gofmt` → `rustfmt` → `zig fmt` → `deno fmt`. Style rules become laws.

### What Mo takes

- **Cargo-style manifest + resolver from v0** ([[d34-packages-are-recipes]], [[q17-package-management-and-supply-chain]]).
- **Rust's ownership + traits + monomorphized generics, generalized to capabilities** ([[d22-rust-plus-refinements-types]], [[d15-effects-via-capabilities]]).
- **Erlang/Elixir process model without the BEAM** ([[d08-beam-qualities-without-the-beam]]).
- **Zig's comptime, allocator explicitness, C-via-Zig toolchain** ([[d24-compile-to-c-via-zig]]).
- **Unison's content-addressing** for reproducible packages.
- **Grammar-constrained decoding friendliness** — LL(1)/LALR(1) grammar so agent code generation stays syntactically valid.

### What Mo refuses

- **npm-style trust defaults.** Post-install scripts, unrestricted transitive install, no capability declarations.
- **Rust's macro complexity.** Procedural macros are agent-hostile.
- **The lazy/pure Haskell substrate.** Strict evaluation only.
- **Class-based OO as the organizing principle.** [[d06-never-oop]] remains.

## Related

- [[plang-history-lambda-to-1970s]]
- [[plang-history-1980s-to-2000s]]
- [[plang-landscape-2026]]
- [[plang-mo-synthesis]]
- [[go-history]] · [[rust]] · [[zig]] · [[elixir]] · [[dependent-types]]
- [[d01-agents-write-the-code]]
- [[d30-supply-chain-security]]

## Sources

- [Full report](../raw/plang-history-2026-09/history/03_2010_to_2026.md)
- [Rust 1.0 announcement](https://blog.rust-lang.org/2015/05/15/Rust-1.0/)
- [Russ Cox, "Minimal Version Selection"](https://research.swtch.com/vgo-mvs)
- [Anthropic, Model Context Protocol](https://www.anthropic.com/news/model-context-protocol)
- [CSA slopsquatting report, 2025](https://cloudsecurityalliance.org/blog/2025/06/03/what-is-slopsquatting-how-ai-hallucinations-are-fueling-a-new-class-of-supply-chain-attacks)
