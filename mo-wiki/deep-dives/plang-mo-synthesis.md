---
title: "Mo synthesis: what history says to Mo"
created: 2026-09-13
updated: 2026-09-13
type: deep-dive
tags: [mo, synthesis, design, history, research]
sources:
  - "../raw/plang-history-2026-09/synthesis/mo_synthesis.md"
---

### Headline

A Mo-specific reading of the 145,000-word research bundle. Mo's design bet is that AI agents will author most Mo code, so annotation cost paid by an agent is worth much more per keystroke than annotation cost paid by a human. Every previous generation of language designers hit the same wall: a property could be enforced in the type system only when the marginal keystroke cost to a *human* was less than the marginal reasoning benefit. When the agent is the author, that wall moves.

### Three findings that shape everything

- **The annotation economy is inverted.** Eiffel's contracts, Ada/SPARK, Clean's uniqueness types, Coq/Agda/Lean, Liquid Haskell, Rust's lifetimes — all crossed the human-cost threshold for specific communities and stayed niche. Agent authorship removes the threshold. See [Peyton Jones, "Wearing the Hair Shirt"](https://simon.peytonjones.org/wearing-the-hair-shirt/) and [Verus](https://arxiv.org/abs/2303.05491).
- **Coherence is the scarcest resource.** No mainstream language has integrated grammar, type system, effect discipline, tooling, and supply-chain security into a coherent whole. Mo has the freedom to do so because its user base is being formed now.
- **The five deliverables that matter for the next six months** (Recommendations 5→1): supply-chain-secured demo registry, RFC process + first three RFCs, package manifest with capability declarations, LSP + tree-sitter + formatter + JSON diagnostics, formal Mo spec.

### Paradigm — pick concepts, not paradigms

Van Roy's *Programming Paradigms for Dummies* frames this exactly: paradigms differ "only in one or a few concepts." Mo's synthesis:

- **From imperative (A1)** — the ability to name what the machine does, with Zig's "no hidden control flow, no hidden allocations" discipline. Directly enables [[d24-compile-to-c-via-zig]].
- **From class-based OO (A2a)** — encapsulation of data with permitted operations. **Not inheritance.** See [[d06-never-oop]].
- **From CLOS/Julia multiple dispatch (A2d)** — available as an idiom, not the primary dispatch.
- **From pure functional (A3)** — Roc's "no side effects except through platforms" ([Roc "Fast"](https://www.roc-lang.org/fast)). Pure-by-default with declared effects.
- **From logic (A5)** — Datalog as an *implementation* technique for the type checker, not user-facing.
- **From concatenative (A6)** — pipeline syntax (`|>`) for readable LLM output.

**Result:** Mo is *pure-by-default, imperative-when-declared, ADT-and-trait-oriented*. It looks to a working Rust or TypeScript programmer like a language they can read on day one.

### Type system — the composed stack

Mo commits to a *composed* type system whose apparent surface is larger than any mainstream language today, but whose annotation cost is agent-paid and human-consumed:

- **Bidirectional type checking** over a small core based on System F. Not full HM inference — global inference produces cascading errors under LLM autofix loops. See [[d22-rust-plus-refinements-types]].
- **Refinement types with SMT dispatch** for functional-correctness contracts. Verus/Dafny/Liquid Haskell/F* model.
- **Region-based memory management with linear/affine handles** for external resources. Cyclone → MLKit → Vale lineage, with explicit `region r { ... }` syntax.
- **Effect rows + capability parameters** on function signatures. Row-type mixing effects and capabilities, e.g. `fn read_config(cap: &FS) -> <read_fs> Config`. See [[d15-effects-via-capabilities]].
- **Structs + traits** with no implementation inheritance; ADTs with exhaustiveness-checked pattern matching as an *error*.

Not adopted: full dependent types (B7) as default, gradual typing (B3), fully inferred HM as the only mode.

### Memory — regions + linear handles

Mo's active repo already has region allocation. This is the leading indicator: **regions as primary memory-management primitive**, with linear/affine handles for external resources.

- **Regions are locally auditable.** `region r { ... }` shows all allocations dying together at the closing brace.
- **Regions do not require lifetime parameters.** Rust's `'a` is the hardest thing to learn; agent-generated regions are explicit, not inferred.
- **Regions compose with linear resources.** External resources (files, sockets, capabilities) are linear-typed; their memory lives in a region. Austral shows the composition.
- **Regions are fast.** O(1) deallocation.

Not adopted: pure Rust-style borrow checking (learning curve), tracing GC (pollutes effect signatures), mutable value semantics (constrains data structures).

### Concurrency — structured on top of effects

Mo adopts **structured concurrency on top of effect handlers**, presented as async/await-style syntax. Reasoning:

- The type system tracks concurrency as an effect (`<async>`, `<par>`).
- The runtime is work-stealing with pre-emption at handler boundaries.
- Every task has a parent scope (Trio / Swift 6 / Kotlin coroutines / JEP 505).
- Data-race freedom via the ownership+capability system, not separate `Send`/`Sync` traits.
- **Actors are a library, not a language primitive.** [[d08-beam-qualities-without-the-beam]] — steal the pattern, not the runtime.

Fallback: Rust-style async/await + structured wrappers if effect handlers prove too complex to ship early.

### Syntax — LL(1)/LALR(1) parseable, familiar to Rust/Swift readers

- Rust-style `fn name(args) -> Ret { body }` and `let x = expr;`.
- Expression-oriented `if`, `match`, blocks.
- Exhaustive pattern matching as an *error*.
- Fixed operator precedence (banning user-defined precedence).
- Canonical formatter (`mo fmt`) with no options.
- Structured JSON diagnostics from day one.
- Reserved keywords: `gen`, `effect`, `region`, `cap`, `contract`, `where`.
- Statement-level annotations: `@requires`, `@ensures`, `@invariant` — dispatched to SMT verifier.

### Compilation — staged, agent-friendly

- **Stage 0** (now): custom VM. Fastest iteration.
- **Stage 1**: Cranelift AOT. ~10× faster compile than LLVM.
- **Stage 2**: LLVM for release throughput.
- **Stage 3**: WebAssembly + Component Model.

C-via-Zig ([[d24-compile-to-c-via-zig]]) is a practical shortcut for reaching every target `zig cc` supports without an LLVM dependency. Not MLIR — overkill for a general-purpose language.

### Package system — the differentiator

Mo has more freedom than any existing ecosystem to design this correctly from scratch. Nine principles:

1. **Content-addressed identifiers, human names as convenience** (Unison + Nix). Typosquatting eliminated at the identifier level.
2. **Manifest declares capabilities.** Import authority is a subset relationship. See [[d34-packages-are-recipes]].
3. **Install/build scripts, procedural macros, native code, FFI default-OFF.** Opt-in per project. Fixes the Cargo `build.rs` and npm `postinstall` anti-patterns.
4. **Publisher identity via OIDC only.** No password-authenticated publishing.
5. **SLSA v1.0 attestations + Sigstore signing** as minimum bar.
6. **Release-age gates.** Default: no dependency published in the last 7 days. Nullifies most supply-chain attacks at negligible cost.
7. **MVS resolution + PubGrub error messages.** Reproducibility with human-readable resolution failures.
8. **Vendor by default.** Ship resolved graph in the repository. Offline-reproducible builds.
9. **Registry federation.** No mandatory central registry.

See [[q17-package-management-and-supply-chain]] and [[supply-chain-defenses]].

### Governance — staged evolution

- **Stage 0 (now, pre-1.0)**: BDFL (Robert). Public RFC process from day one.
- **Stage 1 (post-1.0)**: Steering council. Small (3–5), delegated authority, at least one non-founder.
- **Stage 2**: Foundation. Once corporate adoption is real.

**Do not appoint a successor BDFL.** Guido's model of stepping down without one was correct.

### Lessons from failure

- **Dylan** — killed by Newton cancellation. Lesson: pick a first workload that survives sponsor changes.
- **Fortress** — design ambition outstripped engineering budget.
- **Perl 6 / Raku** — 15 years of scope creep destroyed Perl 5's momentum.
- **Python 2 → 3** — 12 years of ecosystem pain. Backward-incompatible transitions are an emergency mechanism.
- **Scala 2 → 3** — even well-executed migrations cost users.

### Lessons from success (Rust, Go, TypeScript, Elixir)

- Ship the toolchain in one binary (Go).
- Structured JSON diagnostics from day one (Rust).
- A first-class book (Rust, Elixir).
- A first workload (Servo, WhatsApp, Google infra, Phoenix).
- RFC discipline from pre-1.0.
- Compatibility promise + edition mechanism.

### Ten anti-patterns Mo must avoid

1. Ambient authority in package code.
2. Install-time / build-time arbitrary code execution.
3. Whole-program type inference.
4. Indentation-sensitive syntax.
5. User-defined operator precedence.
6. Multiple ways to spell the same thing.
7. Optional semicolons with implicit insertion.
8. Hidden allocations.
9. Global-state singleton APIs.
10. Backward-incompatible major versions without an edition mechanism.

### Five actionable recommendations for the next six months

1. **Publish a formal spec** — EBNF grammar, region semantics, effect-row syntax, type-check algorithm. Rust Reference / Go Spec model.
2. **Ship LSP + tree-sitter + formatter + structured JSON diagnostics** before adding language features.
3. **Design and prototype the package manifest with capability declarations.**
4. **Draft the RFC process; publish RFC 001 (governance), RFC 002 (syntax), RFC 003 (effects/capabilities/regions).**
5. **Ship a supply-chain-secured demo registry** — OIDC auth, content-addressed store, capability subset checking, release-age gate, Sigstore signing, SLSA attestations. Even at toy scale.

Combined, these five set Mo up to be the first language whose response to the AI era is *coherent across all layers*.

## Related

- [[plang-decision-matrix]]
- [[plang-design-camps]]
- [[plang-implementation-menu]]
- [[plang-history-2010-to-2026]]
- [[d01-agents-write-the-code]]
- [[d15-effects-via-capabilities]]
- [[d22-rust-plus-refinements-types]]
- [[d30-supply-chain-security]]
- [[rust]] · [[koka]] · [[austral]] · [[hylo]] · [[roc]] · [[unison]]

## Sources

- [Full Mo synthesis](../raw/plang-history-2026-09/synthesis/mo_synthesis.md)
- [Van Roy, "Programming Paradigms for Dummies"](https://webperso.info.ucl.ac.be/~pvr/VanRoyChapter.pdf)
- [Peyton Jones, "Wearing the Hair Shirt"](https://simon.peytonjones.org/wearing-the-hair-shirt/)
- [Verus arXiv paper](https://arxiv.org/abs/2303.05491)
- [Austral spec](https://austral-lang.org/spec/spec.html)
- [Koka book](https://koka-lang.github.io/koka/doc/book.html)
- [Russ Cox, "Minimal Version Selection"](https://research.swtch.com/vgo-mvs)
- [Rust Foundation launch](https://blog.rust-lang.org/2021/02/08/Foundation-Launch/)
