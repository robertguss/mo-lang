---
title: "Mo design decision matrix"
created: 2026-09-13
updated: 2026-09-13
type: deep-dive
tags: [history, research]
sources:
  - "../raw/plang-history-2026-09/synthesis/decision_matrix.md"
---

### Headline

A menu, not a set of pronouncements. Eighteen design axes, each with mainstream options and a defensible default for Mo. Every choice includes the strongest case for its exemplars — Robert's preferred comparison style — so a future contributor can weigh a divergent choice with the reasoning in hand. When a choice is locked in, the row should be marked **Chosen** with the corresponding RFC number.

### How to read the matrix

- **Implementation cost** is a rough Low/Medium/High engineering estimate for a small team on the existing Mo VM baseline.
- **Reversibility** is how hard the choice is to change after Mo has users — Easy = one edition cycle; Medium = several years of migration; Hard = essentially a new language.
- Each recommendation carries a brief rationale that ties it to [[plang-mo-synthesis]] and the underlying research.

### The eighteen axes

| # | Axis | Options considered | Mo direction | Rationale |
|---|---|---|---|---|
| 1 | **Paradigm blend** | Imperative-first, functional-first, actor-first, OO-first, concatenative, logic, hybrid | Pure-by-default + imperative regions + structs/traits + ADTs + effect rows | Van Roy: pick concepts, not paradigms. Rust-with-Roc/Austral influence. See [[d06-never-oop]]. |
| 2 | **Type-system foundation** | Dynamic, gradual, HM, System F, dependent, refinement, effect-typed, linear, capability | Bidirectional System F + refinements + effect rows + affine handles + capabilities | Larger surface than any one language, but each component has a decade-plus track record. Austral is nearest prior art. [[d22-rust-plus-refinements-types]] |
| 3 | **Memory model** | Manual, RC, tracing GC, ownership+borrowing, regions, linear/uniqueness, generational refs, MVS, hybrid, platform | Regions primary + affine handles on external resources + ORC hybrid escape hatch | Locally auditable; matches Mo's existing VM; sidesteps Rust's lifetime-parameter learning cliff. |
| 4 | **Effect handling** | Implicit, monadic, algebraic handlers, capabilities, none | Algebraic handlers + capability parameters | Composable; unifies exceptions/async/generators; capabilities give compile-time authority. Koka + Austral synthesis. [[d15-effects-via-capabilities]] |
| 5 | **Concurrency** | Threads+locks, CSP, actors, async/await, structured, STM, effect-based, none | Structured concurrency surface over effect-handler runtime; fallback to async/await if handlers slip | Trio/Swift 6/JEP 505 shape; data-race freedom via ownership+capabilities, not `Send`/`Sync`. [[d12-concurrency-at-the-edges]] |
| 6 | **Error handling** | Exceptions, `Result`, error unions, condition system, effect-based, panic-only | Effect-based errors surfaced as `Result<T, E>` sugar (`?` propagation) | Under the hood `throw`/`try` desugar to raising and handling `<exn>` — one primitive, familiar syntax. |
| 7 | **Metaprogramming** | None, text macros, hygienic macros, proc macros, staged compilation, reflection, CTFE | CTFE (Zig-style) + `derive`-only hygienic macros; proc macros default-OFF as opt-in capability | Proc macros are the single largest supply-chain hole in Rust; opt-in fixes it. |
| 8 | **Module system** | Namespace/package, first-class, ML functors, ML signatures, content-addressed | Rust-like modules + explicit interface declarations + content-addressed identity in registry | Familiar user surface; Unison/Nix identity underneath eliminates typosquatting. |
| 9 | **Compilation target** | LLVM, Cranelift, MLIR, custom VM, transpile-to-C, Wasm-first | Custom VM → Cranelift AOT → LLVM release option → Wasm/WASI/Component Model | Fast iteration first; ~10× cheaper compiles than LLVM early; peak throughput later. See [[d24-compile-to-c-via-zig]] as a variant fallback. |
| 10 | **Bootstrapping** | Never self-host, implement-then-self-host, self-host day one, dual-track, bootstrappable-builds | Rust implementation → self-host once type/effect system stable → publish stage-0 seed later | Standard path; premature self-hosting means rewriting the compiler repeatedly. |
| 11 | **Package registry** | Central, federated, content-addressed, git-based, none | Central default (`registry.mo-lang.org`) + federation + content-addressed identifiers under human labels | More permissive than crates.io, more secure than npm, more discoverable than pure Go modules. |
| 12 | **Package authority** | Open trust, signed+verified, capability-declared, sandboxed builds, runtime permission flags | Capability-declared manifests + Sigstore/OIDC signing + sandboxed builds + runtime capability flags | Defense-in-depth. Where Mo's greenfield freedom most pays off. [[d30-supply-chain-security]] · [[q17-package-management-and-supply-chain]] |
| 13 | **Build script policy** | Arbitrary, sandboxed, declarative-only, disabled | Declarative-only by default; sandboxed opt-in per dependency | Fixes npm `postinstall`, Python `setup.py`, Cargo `build.rs`, Rust proc-macros as one class. |
| 14 | **Governance** | BDFL, steering council, foundation, corporate, community RFC | BDFL (Robert) pre-1.0 → steering council post-1.0 → foundation once corporate adoption is real | Publish the governance charter at 1.0 so the transition isn't a surprise. |
| 15 | **Standard library scope** | Batteries-included, curated core, minimal, runtime-provided | Curated core (like Rust); rest as official-but-separate packages | Small enough for one maintainer to review every change. |
| 16 | **Backward compatibility** | Never break, editions, strict semver, major-version breaks, rolling deprecation | Rust-style editions from day one + semver + rolling deprecations | Perl 6 and Python 3 are decisive against major breaks. Include `mo fix --edition` from 0.1. |
| 17 | **Syntax family** | C-family curly, ML expression, Lisp S-expr, indentation, hybrid | C-family curly braces + expression-oriented semantics (Rust/Swift model); LL(1)/LALR(1); mandatory terminators; fixed operator precedence; canonical `mo fmt` | Grammar-constrained LLM decoding, tree-sitter, LSP all trivially implementable. |
| 18 | **Verification integration** | None, refinement (SMT), dependent-adjacent, proof-first, hybrid staged, model checking | Hybrid: ordinary code type-checks; SMT-backed refinement types opt-in via annotations dispatched to Z3; `--verify` flag runs the SMT checks | Where Mo's central design bet — machine verification cheaper than novel syntax — cashes out. Verus/Dafny prior art. [[q08-verification-tiers]] |

### Why the choices reinforce each other

- **Type system + memory + effects**: refinement predicates over regions, affine handles as linear-typed capabilities, effect rows carrying capability parameters. Three features, one integrated system.
- **Effects + concurrency + errors**: async is an effect; cancellation is an effect; errors are an effect. One handler mechanism, one mental model.
- **Syntax + compilation + tooling**: LL(1)/LALR(1) grammar unlocks tree-sitter, LSP, and grammar-constrained LLM decoding without extra work.
- **Manifest + effects + capabilities**: a package's declared capabilities correspond directly to what its function signatures carry. Compiler enforces subset consistency.
- **Bootstrapping + governance + stdlib**: small stdlib is BDFL-maintainable; self-hosting becomes tractable once type/effect system stabilizes; foundation eventually funds ongoing maintenance.
- **Verification + agent authorship + editions**: editions let the verification vocabulary evolve without breaking verified code; agent-supplied annotations amortize verifier cost that would be prohibitive for humans.

### Two provocative alternatives (from the raw)

- **"Rust with better manifest security"** — Keep every Rust axis; move all innovation into supply-chain security (capability manifests, OIDC signing, release-age gates, default-off build scripts). Argument for: minimizes design risk, ships 1.0 faster, ports Rust's tooling knowledge. Argument against: gives up Mo's central bet that agent authorship inverts annotation economics.
- **"Verus/Dafny-shaped, verify-heavy"** — Push further into verification: pure functional first (Roc/F* shape), refinement + dependent-adjacent types, SMT default-on, minimal core, every function contract-annotated. Argument for: maximum machine-verifiability. Argument against: verification cliff is real; risks becoming a research language.

The recommended starting stack sits between them: strictly more security-first than crates.io, strictly less verification-heavy than F*/Dafny, coherent across all layers.

### How to use this as a living document

1. When a decision is locked, mark the row **Chosen** with the RFC that adopted it.
2. When an axis grows a new option (e.g., a new memory-management technique), add a row and re-run the "reinforce each other" checks — an isolated change on one axis often forces revisits elsewhere.
3. Cross-link each Chosen row to its [[d##-...]] direction page and its [[q##-...]] question page.

## Related

- [[plang-mo-synthesis]]
- [[plang-design-camps]]
- [[plang-implementation-menu]]
- [[plang-history-2010-to-2026]]
- [[d09-primary-inspirations]]
- [[d15-effects-via-capabilities]]
- [[d22-rust-plus-refinements-types]]
- [[d30-supply-chain-security]]
- [[q13-implementation-language]]

## Sources

- [Full decision matrix](../raw/plang-history-2026-09/synthesis/decision_matrix.md)
- [Mo synthesis](../raw/plang-history-2026-09/synthesis/mo_synthesis.md)
- [Van Roy, "Programming Paradigms for Dummies"](https://webperso.info.ucl.ac.be/~pvr/VanRoyChapter.pdf)
- [Austral spec](https://austral-lang.org/spec/spec.html)
- [Koka book](https://koka-lang.github.io/koka/doc/book.html)
- [Rust editions guide](https://doc.rust-lang.org/edition-guide/)
- [Cranelift](https://cranelift.dev/)
- [Verus paper](https://arxiv.org/abs/2303.05491)
- [SLSA specification](https://slsa.dev/spec/v1.0/levels)
