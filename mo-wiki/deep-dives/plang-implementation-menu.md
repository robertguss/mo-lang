---
title: "Implementation menu: what a language builder chooses"
created: 2026-09-13
updated: 2026-09-17
type: deep-dive
tags: [tooling, history, research]
sources:
  - "../raw/plang-history-2026-09/camps/implementation_engineering.md"
contested: true
contradictions: [01-premise, d24-compile-to-c-via-zig, q13-implementation-language]
---
# Implementation menu: what a language builder chooses

> **17 Sep 2026.** This page is the 13 Sep synthesis of an external research run. The Mo it describes — brace syntax, effect rows, a Rust implementation, a package registry, an RFC process — was never Mo's design. Mo's decisions are the spec chapters under `spec/design-v0/` and the [[decision-log]]. Read this page as landscape only.

## Headline

A new language is a stack of engineering decisions. Some are visible (syntax, type system, memory model); most are invisible (parser strategy, IR choice, GC algorithm, package resolver). The invisible ones determine whether the language *ships* and whether developers *want* to use it. The raw report walks through eleven sections; this page distills the menu for Mo.

## Three findings that shape everything

- **Hand-written recursive descent + Pratt beats generators for production compilers.** Better error messages, incremental-tooling compatibility, faster code, easier context-sensitive tokens. Almost every successful modern compiler ships this stack.
- **Type checking should be bidirectional, not fully HM-inferred.** Bidirectional propagation gives local error messages, easier IDE integration, and composability with refinements and effects.
- **Tooling ships with the language or it doesn't ship at all.** `gofmt`, `rustfmt`, LSP, package manager, docgen — all bundled from day one, in every language that has succeeded since 2010.

## Section 1 — Lexing and parsing

- **Lexer**: hand-written, not `lex`/`flex`. Better errors, context-sensitive tokens, incremental tooling.
- **Parser**: hand-written recursive descent for the outer skeleton; Pratt (Vaughan Pratt, 1973) for expressions.
- **Generator alternatives** (yacc/bison, ANTLR ALL(\*), Menhir, LALRPOP) — good for teaching, DSLs, and languages that need machine-verifiable grammars. Not the default for Mo.
- **Error recovery**: production-grade parsers need tentative parsing, skip-to-synchronizing-token strategies, and typed AST holes for incomplete input.

Mo direction: hand-written RD + Pratt, LL(1)/LALR(1)-friendly grammar for [[q13-implementation-language]] compatibility.

## Section 2 — Intermediate representations

- **AST → typed AST → HIR → MIR → LIR** is the modern shape.
- **SSA (static single assignment)** is the middle-end lingua franca. Every serious optimizer uses it.
- **CPS (continuation-passing style)** works for functional languages (Standard ML of NJ pioneered).
- **ANF (A-normal form)** is a lightweight SSA cousin used in Roc, Erlang, Zig.
- **MLIR** (LLVM Foundation) offers a multi-level IR with reusable dialects — the modern option for languages that want to reach GPUs and accelerators.

Mo direction: typed AST → MIR → C emission. LLVM/Cranelift optional later.

## Section 3 — Type checking algorithms

- **Hindley-Milner (Algorithm W, Algorithm J)** — the classic, full inference.
- **Bidirectional type checking** (Pierce & Turner) — annotations at function boundaries; propagates inward. Better error messages.
- **Elaboration** — desugars surface syntax into a smaller core language before checking (Haskell's Core, Rust's HIR/MIR, Lean's terms).
- **Row polymorphism** for records and effect systems.
- **Refinement type checking** delegated to SMT solvers (Z3, CVC5).
- **Trait / type-class resolution** via Wadler dictionaries or monomorphization.

Mo direction: bidirectional System F + row types + refinements + effects (see decision matrix).

## Section 4 — Memory management

- **Manual + capabilities** — Zig's allocator model.
- **RAII + destructors** — C++ / Rust.
- **Refcounting** — Swift, Objective-C ARC. Predictable, cycle-limited.
- **Tracing GC** — Java, Go, .NET. Copying, generational, concurrent. Best throughput; worst latency floor.
- **Region-based** — Cyclone, MLKit, Vale. Deallocate whole regions.
- **Ownership + borrowing** — Rust's borrow checker.
- **Linear types** — Clean, Austral, Granule.
- **Hybrid** — Roc platforms, Nim ARC/ORC, Swift ownership additions.

Mo direction: regions + capabilities as primary; RAII at scope boundaries; capability-declared allocator per runtime.

## Section 5 — Runtimes and VMs

- **Custom VM** (Erlang BEAM, Lua, Python) — full control; long build time.
- **Cranelift** — Rust's faster JIT; Wasmtime; production-grade.
- **LLVM** — the industry standard back end; slow compile but excellent codegen.
- **GCC** — mature; slower to iterate.
- **C emission** — the classic hack; free portability; slower type-checked release cycle.

Mo direction: C emission via `zig cc` for release ([[d24-compile-to-c-via-zig]]); tree-walking interpreter for edit-loop. Cranelift later if needed.

## Section 6 — Concurrency implementation

- **OS threads** — the substrate; too heavy for high fan-out.
- **Green threads** — M:N scheduling. BEAM, Go goroutines, Java virtual threads.
- **Stackless coroutines** — Rust `async`, C++20, JS.
- **Fibers / stackful coroutines** — Boost, Lua, Ruby fibers.
- **Work-stealing schedulers** — Tokio, ForkJoinPool, Cilk, Rayon.
- **Actor mailboxes** — Erlang, Pony.

Mo direction: structured concurrency + capability-declared runtimes. Multiple runtime backends selected per capability.

## Section 7 — Package managers and dependency systems

**The big three algorithms:**

- **SAT-based resolvers** (npm, Cargo) — powerful; can produce surprising builds.
- **Minimum Version Selection** (Go modules, Russ Cox 2018) — pick minimum satisfying constraint. Reproducible by construction.
- **PubGrub** (Dart's pub; adopted by uv, Cargo experimentally) — better error messages than SAT; still SemVer-based.

**Other essentials:**

- Lockfiles pinning transitive versions.
- Content-addressed caches (Nix, Unison, Bazel).
- Cryptographic transparency logs (`sum.golang.org`, sigstore).
- Capability manifests (proposed for Mo — [[d34-packages-are-recipes]]).

Mo direction: MVS + content-addressed store + capability manifests + transparency log. See [[q17-package-management-and-supply-chain]].

## Section 8 — Tooling ecosystem

- **LSP** (Language Server Protocol, Microsoft) — one server, every editor. Non-negotiable.
- **tree-sitter** (Max Brunsfeld) — incremental parsing for editors and query-based linters.
- **Formatter** — `gofmt` model, one canonical style, applied by default ([[d04-style-rules-become-laws]]).
- **Linter** — `clippy`-style, in the toolchain.
- **Test runner + coverage** — built in.
- **Docgen** — Rust-style hyperlinked, comment-derived docs.
- **Build system** — Cargo-style, one command.
- **Debugger integration** — DAP (Debug Adapter Protocol).

Mo direction: all of the above, bundled, from v0.

## Section 9 — Verification and formal methods integration

- **SMT solvers** — Z3, CVC5. The workhorse for refinements.
- **Model checkers** — TLA+ (Lamport), Alloy — for specifying and checking designs, not code.
- **Proof assistants** — Lean, Coq/Rocq, Isabelle, F*. Full functional-correctness proofs.
- **Automated verifiers** — Dafny, SPARK, Verus, Prusti, Creusot — a middle ground; SMT-backed program verifiers.

Mo direction: tiered ([[q08-verification-tiers]]). Ordinary code type-checks. Capability-guarded code discharges refinement obligations via SMT. High-assurance code can escalate to Lean/F*-style proofs.

## Section 10 — Bootstrapping

- **Trusted first compiler** — Rust started in OCaml; Zig started in C++; SBCL started in C.
- **Self-hosting** — the milestone that says the language is real.
- **Reproducibility** — Bootstrappable Builds project. Every serious language should target it.

Mo direction: implementation in Zig ([[q13-implementation-language]]), self-hosting when maturity permits.

## Section 11 — Documentation and community engineering

- **The Book** (Rust, Elixir, Zig) — one canonical intro.
- **The Reference** — spec-level detail.
- **API docs** — auto-generated from source.
- **RFC process** — Rust-style structured proposals.
- **Governance** — how decisions get made and by whom.

## What changes when the language is for AI

- **Small, stable grammar** so grammar-constrained decoding stays cheap.
- **Explicit imports and dependencies** with capability declarations.
- **Machine-verifiable contracts** for spec-carrying source ([[d02-spec-altitude]], [[d03-source-carries-its-evidence]]).
- **Deterministic tooling** — repeatable builds are a security property, not a convenience.

## Sources

- [Full report](../raw/plang-history-2026-09/camps/implementation_engineering.md)
- [Wirth, *Compiler Construction*](https://people.inf.ethz.ch/wirth/CompilerConstruction/CompilerConstruction1.pdf)
- [Crockford, *Top Down Operator Precedence*](https://www.crockford.com/javascript/tdop/tdop.html)
- [Russ Cox, "Minimal Version Selection"](https://research.swtch.com/vgo-mvs)


## Related

- [[plang-design-camps]]
- [[plang-mo-synthesis]]
- [[plang-decision-matrix]]
- [[compilation-target-and-compile-speed]]
- [[q13-implementation-language]]
