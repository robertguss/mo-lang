---
title: "Mo vs Roc"
created: 2026-09-12
updated: 2026-09-17
type: comparison
tags: [research, runtime, compiler]
sources: [raw/articles/feldman-roc-rust-to-zig.md, raw/articles/roc-platform-template-main-roc.md, raw/articles/roc-platform-template-rust.md, raw/articles/roc-mini-tutorial-new-compiler.md, raw/articles/roc-functional.md, raw/articles/roc-langref-functions.md, raw/articles/roc-langref-static-dispatch.md, raw/articles/roc-langref-expressions.md]
confidence: medium
---

# Mo vs Roc

**One line:** the language Mo's platform split comes from ([[q11-platform-and-stdlib|Q11]]), and the project whose Rust-to-Zig rewrite backs Mo's toolchain choice ([[q13-implementation-language|Q13]]); on the list to see how a platform is actually built and what the rewrite really measured.

## What it is (status as of Sep 2026)

Roc is a pure functional language with automatic memory management through reference counting. It is "not a systems language".[35] Its new compiler, rewritten from Rust into Zig, reached feature parity after 487 days. It is now about 464K lines of Zig, and version 0.1.0, Roc's "first-ever numbered release", is planned for later in 2026.[35] Most published platforms still target the old compiler.[42] Richard Feldman leads it. Roc can run in the browser on the homepage through a 2.5MB WebAssembly build.[35]

## The ideas, one by one

- **Platforms, concretely.** An app names its platform by URL, for example `app [main!] { pf: platform "https://…tar.zst" }`.[43] A platform is a Roc header plus a native host library, one per target:[44]
  ```roc
  platform ""
      requires { main! : List(Str) => Try({}, [Exit(I32), ..]) }
      exposes [Stdout, Stderr, Stdin]
      provides { "roc_main": main_for_host! }
      hosted { "roc_stdout_line": Host.stdout_line! }
      targets: { x64musl: { inputs: ["crt1.o", "libhost.a", app, "libc.a"] } }
  ```
  `requires` fixes the shape of the app's `main!`. `hosted` lists functions implemented by the host, written in Rust or another systems language with generated ABI bindings.[43] `targets` lists the link inputs. "Roc's standard library does not include any effectful functions; they all come from the platform."[42]
  - *Mo today:* the language has no I/O. `main(platform: Platform)` receives it, and `Mo.Server` and `Mo.Sim` ship as platforms ([[q11-platform-and-stdlib|Q11]], [[p13-capabilities-and-logging|pick 13]]).
  - *Verdict:* **already have** the split. **Steal** the header's five parts as the template for a Mo platform manifest. One difference: Roc exposes effects as *modules* any effectful function may call, while Mo hands them out as *values*, so authority is finer.

- **Purity by arrow, not by capability.** Pure function types use `->` and effectful ones `=>`, and effectful names end in `!`.[40] Pure code cannot call effectful code. The compiler infers which is which. Roc has no effect polymorphism "by design".[40] Roc dropped its old `Task` design for direct calls. The platform decides whether effects run as blocking or async I/O.[38]
  - *Mo today:* pure unless a capability is passed ([[d15-effects-via-capabilities|direction 15]]). Direct-style I/O with runtime interception ([[d16-direct-style-io|direction 16]]).
  - *Verdict:* **already have**, with finer grain. Roc's move away from `Task` is independent support for [[d16-direct-style-io|direction 16]]. Its missing effect polymorphism has a cost: `Try.map_ok` and `Try.map_ok!` both exist.[40] Mo avoids the duplication only because a closure can capture a capability, and that capture hides effects from signatures (see [[koka]]).

- **Compile-time evaluation of pure code.** "All top-level values are evaluated at compile time." A crash during that evaluation becomes a compile error.[40]
  - *Mo today:* not discussed. There are no globals ([[d14-processes-are-the-only-identity|direction 14]]), but constants are unaddressed.
  - *Verdict:* **open.** It fits Mo: purity is visible in the signature, and a crash at build time is better than one in production.

- **Static dispatch replaced abilities.** Methods live in a block on the nominal type, `Counter := { value: I64 }.{ … }`.[39] Generic requirements are per method, `where [encoding.parse_str : encoding, state -> …]`.[39] Some method names (`is_eq`, `to_hash`) opt a type into syntax, and six can be derived by writing `_`. "Dynamic dispatch is unsupported by design."[39]
  - *Mo today:* named `trait` plus `impl … for`, `where T: Comparable`, and no trait objects in v1 ([[p15-methods-traits-generics|pick 15]]).
  - *Verdict:* **open.** Roc's design has no coherence problem, because a method can only be defined in its type's own block (see [[rust]]). It also means no one can add `Comparable` to a type they don't own. Mo's named traits read better at spec altitude.

- **Perceus memory with local `var`.** Builtins mutate in place when a refcount is 1 and shallow-clone otherwise.[41] Closure captures don't heap-allocate, thanks to lambda-set defunctionalization. That implementation was hard enough to push the team into a full rewrite.[35] Locals can be reassigned only with a `$` on every use (`var $total = 0`). A nested function "cannot reassign a variable captured from an outer function".[38]
  - *Mo today:* Perceus-style reuse ([[d10-immutable-by-default|direction 10]]). `var` never escapes its function ([[d13-local-var-and-inout|direction 13]]).
  - *Verdict:* **already have** the model, and Roc's capture rule is the same as direction 13. **Reject** the `$` sigil, which fails Mo's syntax taste. **Open:** lambda-set specialization for Mo's C backend is fast but costly to build.

- **Hot loading in development, a native binary for release.** `roc server.roc` hot-loads code changes into a running server; `roc build` produces an LLVM-optimized self-contained binary.[35] Examples run through an interpreter.[43]
  - *Mo today:* the interpreter is a dev tool, never shipped ([[d25-interpreter-for-the-edit-loop|direction 25]]). [[steal-list]] says "leave hot reload".
  - *Verdict:* **open.** Hot loading that exists only in development could fall out of the direction-25 interpreter at no release cost.

  Answered since (17 Sep 2026): recorded as [[d39-hot-code-reload]]; nothing has been built, deliberately.

## What it gives up

- **Effect polymorphism.** Higher-order helpers come in pure and `!` pairs.[40] Mo avoids this through closure capture, at a cost to purity reasoning ([[koka]]).
- **Dynamic dispatch.** None at all.[39] Mo makes the same cut for v1.
- **Stability.** No numbered release yet, and most platforms are on the old compiler.[42] The Zig toolchain treats backwards compatibility as a non-goal at this stage.[35] Mo takes on this same risk by choosing Zig.
- **Warnings.** A missing `!` or a wrong purity annotation is only a warning.[40] Mo has no warnings ([[q09-compiler-diagnostics|Q9]]).

## Evidence

Everything below comes from Feldman's July 2026 retrospective.[35] An incremental rebuild means a trivial parser edit.

| Compiler | Cold build | Incremental |
|---|---|---|
| Rust 1.85, 354K lines | 32.4s | 10.0s |
| Rust 1.97, 354K lines | 25.4s | 3.4s |
| Zig 0.16, 320K (parity) | 39.6s | 8.6s |
| Zig 0.17 nightly, 464K | 32.1s | 0.035s |

- **The 35ms is not yet in hand.** Stable Zig 0.16 has a bug that breaks `-fincremental` on Roc's code, and incremental compilation works only on x86-64. The team is waiting for the next stable Zig.[35]
- **Bugs:** Claude Opus 4.8 classified the issue tracker. The Rust compiler had 21 memory-corruption bugs among 2,596 total, the Zig compiler 10 among 431. Feldman: "picking a different row would have made no appreciable difference".[35]
- **`unsafe`:** the Rust compiler used about 1,200 `unsafe` blocks in 300K lines.[35]
- **Caching:** compiler data lives in arrays indexed by 32-bit integers, not pointers, so a cache loads from disk "at roughly the speed of memcpy". `roc test` caches outcomes of pure-function tests, per file.[35]

## What Mo should take from this

- **Proposal:** a Mo platform manifest in Roc's five parts. `requires` is the shape of `main`, `exposes` the capability modules, `provides` the entry symbol, `hosted` the native functions, `targets` the link inputs per target (joins [[q11-platform-and-stdlib|Q11]] and [[d24-compile-to-c-via-zig|direction 24]]).
- ⚠️ **Nuance to [[q13-implementation-language|Q13]]'s stated reason** ("got 100x faster incremental builds"). The measured 35ms needs a Zig nightly on x86-64. On stable Zig at parity, Roc's incremental rebuild was 8.6s against Rust 1.97's 3.4s.[35] The other Zig reasons (one toolchain, cross-compilation, arenas) are untouched. Not resolved here.
- **Proposal:** from day one, pointer-free, index-based compiler data with a load-without-parsing disk cache ([[d23-compile-speed-first-class|direction 23]]). Also cache test outcomes by hash ([[p12-tests|pick 12]]), which Roc already does per file.
- **Question for Robert:** keep named traits with `impl … for`, or take Roc's per-method `where` with methods only in the type's block? The second removes the coherence question and loses impls on types you don't own.
- **Question for Robert:** hot code loading in development only, served by the direction-25 interpreter, or stay with the steal list's "leave hot reload"?

  Answered since (17 Sep 2026): [[d39-hot-code-reload]] holds the answer; nothing built yet, deliberately.
- **Proposal:** evaluate pure top-level constants at compile time, and treat a crash there as a compile error.[40]

## Related
- [[language-landscape]]
- [[q11-platform-and-stdlib]]
- [[q13-implementation-language]]
- [[d24-compile-to-c-via-zig]]
- [[d25-interpreter-for-the-edit-loop]]
- [[d15-effects-via-capabilities]]
- [[p15-methods-traits-generics]]
- [[rust]]
- [[d39-hot-code-reload]]

## Sources

[35] https://rtfeldman.com/rust-to-zig — How Our Rust-to-Zig Rewrite is Going (Feldman, 2026)
[38] https://www.roc-lang.org/functional — Roc: Functional
[39] https://www.roc-lang.org/docs/main/langref/static-dispatch — Roc language reference: Static Dispatch
[40] https://www.roc-lang.org/docs/main/langref/functions — Roc language reference: Functions (purity inference)
[41] https://www.roc-lang.org/docs/main/langref/expressions — Roc language reference: Expressions (opportunistic mutation)
[42] https://github.com/roc-lang/roc/blob/main/docs/mini-tutorial-new-compiler.md — Roc mini-tutorial for the new compiler
[43] https://github.com/lukewilliamboswell/roc-platform-template-rust — Roc platform template (Rust host)
[44] https://raw.githubusercontent.com/lukewilliamboswell/roc-platform-template-rust/main/platform/main.roc — Roc platform template: platform/main.roc
