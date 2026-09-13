# Rust — Memory Safety Without Garbage Collection

## Origin story

### Designer, institution, year

Rust was created by **Graydon Hoare**. "Rust began in 2006 as Hoare's personal project while he was a Mozilla employee" ([Wikipedia: Rust](https://en.wikipedia.org/wiki/Rust_(programming_language))).

The origin anecdote: "According to *MIT Technology Review*, Hoare started the project after frustration with a broken elevator in his apartment building whose software had crashed" ([Wikipedia: Rust](https://en.wikipedia.org/wiki/Rust_(programming_language))). "Hoare named the language after fungi of the same name that are 'over-engineered for survival.'"

Timeline:

| Milestone | Date |
|---|---|
| Started as Hoare's side project | 2006 |
| Mozilla officially sponsored | 2009 |
| Ownership system in place | 2010 |
| Rust 0.1 (first public release) | January 20, 2012 |
| Hoare stepped down from Rust | 2013 |
| Rust 1.0 | May 15, 2015 |
| Rust Foundation established | February 8, 2021 |
| Rust in Linux kernel (6.1) | December 2022 |

([Wikipedia: Rust](https://en.wikipedia.org/wiki/Rust_(programming_language)))

The first compiler was written "in approximately **38,000 lines of OCaml**"; then "development shifted from the OCaml compiler to a self-hosting compiler written in Rust and targeting LLVM."

### The motivating problem

Mozilla wanted a systems language that could safely handle the concurrency and memory management demands of a modern browser engine. Firefox's C++ codebase had spent 20 years accumulating use-after-frees, buffer overflows, and data races; a memory-safe replacement was the strategic goal. This became Servo (Mozilla's experimental browser engine, 2012–2020), which drove Rust's ownership design forward.

The engineers Mozilla placed on the project — "**Patrick Walton, Niko Matsakis, Felix Klock, and Manish Goregaokar**" ([Wikipedia: Rust](https://en.wikipedia.org/wiki/Rust_(programming_language))) — brought PL-theory rigor (Matsakis's dissertation work on ownership and regions is the technical foundation of the borrow checker).

### Initial reception

Cautiously optimistic 2012–2015, with rapid iteration and painful churn (green threads were removed in 0.7; the old task system was removed; the trait system was reworked; syntax evolved). Rust 1.0 in 2015 marked the stability commitment. Enthusiasm exploded 2016–2018 as ergonomics improved (`?` operator, non-lexical lifetimes 2018). By 2020, Rust had won Stack Overflow's "most loved language" survey for five years running.

## Design philosophy

### Core principles

- **Memory safety without garbage collection.** The signature.
- **Zero-cost abstractions.** Following Stroustrup: "what you don't use, you don't pay for."
- **Fearless concurrency.** The borrow checker prevents data races statically.
- **Explicit is better than implicit** for allocation, error handling, mutability.
- **Guaranteed absence** of null pointer dereferences (via `Option`), buffer overflows, use-after-free, data races — in safe code.

### What Rust rejected

- **Garbage collection.** Ownership + RAII instead.
- **Exceptions.** `Result<T, E>` and `?` propagation.
- **Nulls.** `Option<T>`.
- **Implicit conversions.** Even `i32` → `i64` requires an explicit `as` cast.
- **Uncontrolled mutability.** Immutable by default; `mut` opts in.
- **Inheritance.** Traits (with default methods) and composition.

### Cultural values

Correctness by default; documentation as first-class artifact; community-driven RFC process; "the compiler is your friend" (error messages are famously helpful); refusal to compromise the safety guarantee to gain adoption.

## Language features

### Syntax

C-derived braces plus ML-derived expression-orientation. `let`, `let mut`, `fn`, `struct`, `enum`, `impl`, `trait`. Pattern matching with `match`. Closures. Explicit lifetime parameters `'a`. Turbofish (`::<T>`) for explicit type arguments.

### Type system

Strong, static, type-inferred (Hindley-Milner-ish for local inference). Generics with trait bounds; associated types; higher-ranked trait bounds. **Traits** are Rust's version of Haskell type classes.

**Notable features:**
- **Enums as sum types** (algebraic data types).
- **Pattern matching** with exhaustiveness checking.
- **Marker traits**: `Send`, `Sync`, `Copy`, `Sized`.
- **Coherence rules** (orphan rule).
- **Const generics** (stabilized 1.51, 2021).
- **GATs** (Generic Associated Types, 2022).
- **`impl Trait`** in return and argument positions.
- **`async`/`await`** (stabilized 1.39, November 2019).

### Memory model — the borrow checker

"Rust enforces memory safety without a conventional garbage collector. The borrow checker tracks the object lifetime of references at compile time. The ownership system ensures memory safety without using a garbage collector" ([Wikipedia: Rust](https://en.wikipedia.org/wiki/Rust_(programming_language))).

Rules:
- "Each value must be attached to a variable called the **owner**. Every value must have exactly one owner. Values can be moved between owners through assignment or by passing a value as a function parameter. Values can be borrowed, meaning they are temporarily passed to another function before being returned to the owner."
- "Rust types are known as **affine types**, meaning each value may be used at most once."
- "When a value goes out of scope, it is dropped by running its destructor. A destructor may be defined programmatically by implementing the `Drop` trait."
- "Rust separates: Shared, immutable references of the form `&T`; Unique, mutable references of the form `&mut T`. A mutable reference can be coerced to an immutable reference, but not the reverse. Built-in reference types using `&` do not involve run-time reference counting."

**Lifetimes:** "An object lifetime is the period during which a reference is valid, from object creation to destruction. Lifetimes are implicitly associated with all Rust reference types. Lifetimes are often inferred but can also be specified explicitly with named lifetime parameters, often written as `'a`, `'b`" ([Wikipedia: Rust](https://en.wikipedia.org/wiki/Rust_(programming_language))).

**Unsafe escape hatch:** "Rust's safety guarantees include memory safety, type safety, data-race freedom. These guarantees can be circumvented with `unsafe`. `unsafe` permits programmers to dereference arbitrary raw pointers, call external code, perform low-level operations not allowed by safe Rust. Unsafe code is needed, for example, to implement some data structures. The page states that doubly linked lists are difficult or impossible to implement in safe Rust" ([Wikipedia: Rust](https://en.wikipedia.org/wiki/Rust_(programming_language))).

Google's Android team reports "Approximately **4% of Rust code is written within `unsafe{}` blocks**" ([Google Android Rust blog](https://blog.google/security/rust-in-android-move-fast-fix-things/)).

### Concurrency

`std::thread` for OS threads. `Send` and `Sync` marker traits enforce data-race-free sharing at compile time. Channels via `std::sync::mpsc`. **Async/await** using futures (Tokio, async-std as major runtimes).

Rust does not ship an async runtime in stdlib — a controversial choice: apps pick Tokio (dominant), async-std, smol, or embassy (embedded).

### Error handling

`Result<T, E>` and `Option<T>` with the `?` operator for propagation. `panic!` for unrecoverable errors. **No exceptions.**

### Metaprogramming

Two macro systems:
- **Declarative macros** (`macro_rules!`) — pattern-based, hygienic.
- **Procedural macros** — custom `#[derive]`, attribute-like, function-like — operate on `TokenStream`. Serde, Rocket, Diesel, Tokio, sqlx all rely heavily on proc macros.

### Module system

Modules and crates with a strict privacy model. **Cargo** is the build system and package manager.

## Implementation

### Reference compiler

**`rustc`** — the Rust compiler, written in Rust, using LLVM as backend. Being augmented by **`rustc_codegen_gcc`** (GCC backend) and **`rustc_codegen_cranelift`** (Cranelift backend, fast debug builds).

### Lexer, parser, IR, backend

Hand-written lexer and parser produce AST → HIR (High-level IR) → THIR (Typed HIR) → MIR (Mid-level IR, where the borrow checker runs) → LLVM IR → machine code. MIR was introduced in 2016 and enabled non-lexical lifetimes (NLL, 2018) and Polonius (next-generation borrow checker, in progress).

### Runtime

Very small — essentially the panic runtime, stack unwinding, and thread-local storage. No GC. `no_std` mode strips even more for embedded targets.

### Bootstrapping

Self-hosted; requires previous stable Rust to build current stable (with stage0 → stage1 → stage2 process). `rustc-perf` benchmarks compile-time regression.

### Alternative implementations

- **`gccrs`** — GCC front-end for Rust, in progress.
- **`mrustc`** — an alternate Rust-to-C compiler used for verifying rustc bootstrap.
- **Miri** — an interpreter for MIR used to detect undefined behavior.
- **kani** — model checker for Rust.

## Ecosystem

### Package manager — Cargo

"Cargo is Rust's build system and package manager. Cargo: Downloads packages, Compiles packages, Distributes packages, Uploads packages. Rust packages are called **crates**. Crates are maintained in an official registry" ([Wikipedia: Rust](https://en.wikipedia.org/wiki/Rust_(programming_language))).

`crates.io` is the community registry; `docs.rs` auto-hosts documentation for every published crate. `Cargo.toml` (manifest) and `Cargo.lock` (lockfile) support reproducible builds.

### Standard library

Deliberately small: `std::collections`, `std::io`, `std::sync`, `std::thread`, `std::net`, `std::fs`. Anything larger — HTTP, TLS, JSON, async — lives in the ecosystem.

Key crates: **serde** (serialization), **tokio** (async runtime), **hyper** (HTTP), **reqwest** (HTTP client), **axum** and **actix-web** (web frameworks), **clap** (CLI), **anyhow** and **thiserror** (errors), **rayon** (data parallelism), **ndarray** (numerical), **polars** (DataFrame — Rust-native pandas competitor), **wgpu** (portable GPU).

### Tooling

**rustup** — toolchain manager. **rust-analyzer** — LSP (now the official one). **rustfmt** — formatter. **clippy** — linter with hundreds of lints. **cargo-audit** — vulnerability scanner. **miri** — UB detector. **cargo-flamegraph**, **cargo-bench**, **cargo-fuzz**.

### Governance

**Rust Foundation** established February 8, 2021. "Founding companies: Amazon Web Services, Google, Huawei, Microsoft, and Mozilla Foundation." Platinum members as of 2026: "ARM, Amazon, Google, Huawei, Meta, Microsoft, and OpenAI" — with "OpenAI, which joined in June 2026" ([Wikipedia: Rust](https://en.wikipedia.org/wiki/Rust_(programming_language))).

Technical decisions flow through the RFC process on GitHub; teams (compiler, lang, libs, cargo, infra, etc.) drive their areas.

### Release cadence

"After Rust 1.0, new features are developed in **nightly** versions released daily. During each **six-week release cycle**: Changes in nightly versions are released to beta. Changes from the previous beta version are released to a new stable version. A new Rust **edition** is produced every two or three years" (2015, 2018, 2021, 2024). "Editions allow limited breaking changes, such as promoting `await` to a keyword" ([Wikipedia: Rust](https://en.wikipedia.org/wiki/Rust_(programming_language))).

## Adoption

### Where Rust has landed

**Android platform.** Google's landmark 2025 report ([Google Android Rust blog](https://blog.google/security/rust-in-android-move-fast-fix-things/)) demonstrated:

| Metric | Rust vs C++ |
|---|---|
| Memory-safety vulnerability density | ~1,000x lower |
| Revisions required per change | ~20% fewer |
| Time in code review | ~25% less |
| Rollback rate for medium/large changes | ~4x lower |

"Memory-safety vulnerabilities as a share of total vulnerabilities in 2025: **Below 20% for the first time**." Android's Rust code is estimated at **~5 million lines** with only **one** potential memory-safety vulnerability found — "0.2 vulnerabilities per million lines of code," versus "closer to 1,000 vulnerabilities per million lines of code" historically for C/C++ ([Google Android Rust blog](https://blog.google/security/rust-in-android-move-fast-fix-things/)). See also the community discussion ([Reddit r/rust](https://www.reddit.com/r/rust/comments/1ozomgq/rust_adoption_drives_android_memory_safety_bugs/)).

**Linux Kernel.** Rust support merged in Linux 6.1 (December 2022). "Android's 6.12 Linux kernel is Android's first kernel with Rust support enabled, Android's first kernel with a production Rust driver" ([Google Android Rust blog](https://blog.google/security/rust-in-android-move-fast-fix-things/)).

**Windows.** Microsoft has been rewriting core Windows components in Rust (`win32k`, DirectWrite portions). CEO David Weston and CTO Mark Russinovich have publicly endorsed Rust migration.

**Firefox.** Servo lineage lives on in Stylo (CSS), WebRender.

**Cloud infrastructure.** **AWS Firecracker**, **Cloudflare Workers** (V8 wrapped in Rust), **Deno**, **Fastly Compute**, **Tailscale** (parts), **Discord** (chat services), **1Password** (Rust core), **Dropbox** (Magic Pocket rewrite in Rust).

**Developer tooling.** **ruff** (Python linter), **uv** (Python package manager), **turbopack**, **swc**, **biome**, **fd**, **ripgrep**, **bat**, **exa**, **starship** — many CLI tools that beat their predecessors on speed.

**Databases.** TiKV (CockroachDB competitor), SurrealDB, Neon (Postgres branching), InfluxDB IOx.

**Cryptocurrency/blockchain.** Solana, Polkadot, Foundry, Reth.

### Where Rust struggles

- **GUI applications** — Tauri and egui and iced help; still less mature than Qt/Electron.
- **Data science** — Polars is compelling, but Python owns the ecosystem.
- **Web frontend** — Yew, Leptos, Dioxus exist but marginal.
- **Rapid prototyping** — the borrow checker imposes friction.

### Current momentum (2026)

Very strong. Stack Overflow "most admired language" for eight consecutive years (2016–2023, continuing). Government and industry safe-coding recommendations (NSA, CISA, White House ONCD 2024) explicitly cite Rust. **OpenAI joining the Rust Foundation as Platinum member (June 2026)** signals continued momentum ([Wikipedia: Rust](https://en.wikipedia.org/wiki/Rust_(programming_language))).

## Criticism and open problems

- **Steep learning curve.** The borrow checker, lifetimes, async, and the ecosystem's macro-heaviness overwhelm newcomers.
- **Long compile times.** Cargo caching helps, but from-scratch builds are slow. `cranelift` speeds debug; incremental compilation improves.
- **Async ecosystem fragmentation.** No standard runtime; Tokio, async-std, smol, embassy, monoio compete; incompatible executors.
- **Self-referential structs / linked lists / graphs** are notoriously awkward in safe Rust.
- **`Send`/`Sync` bounds** in async can be viral.
- **Compiler binaries are large.**
- **The GATs / higher-kinded types debate** — Rust has partial support; full HKTs are unlikely.

## Influence on other languages

- **Swift** — evolved toward Rust-like ownership with 2024's noncopyable types and `borrow`/`inout`.
- **C++** — the Safe C++ (Sean Baxter) proposal and Herb Sutter's Cpp2 both borrow Rust ideas.
- **Carbon** (Google) — successor-to-C++ language, cites Rust as inspiration but keeps C++ interop primary.
- **Val / Hylo** — mutable value semantics language inspired by Rust's ownership.
- **Vale** — region-based memory-safe language.
- **Nickel**, **Roc**, **Gleam** — cite Rust's ML-derived expression orientation.

## Key sources

- Aaron Turon and Niko Matsakis, ["Fearless Concurrency with Rust"](https://blog.rust-lang.org/2015/04/10/Fearless-Concurrency.html), 2015.
- Niko Matsakis, PhD dissertation on regions and ownership, ETH Zurich, 2011.
- Rust reference: [doc.rust-lang.org/reference/](https://doc.rust-lang.org/reference/).
- The Rust Book: [doc.rust-lang.org/book/](https://doc.rust-lang.org/book/).
- Jeff Vander Stoep and Google Android Security team, ["Rust in Android: Move Fast and Fix Things"](https://blog.google/security/rust-in-android-move-fast-fix-things/), 2025.
- [Wikipedia: Rust (programming language)](https://en.wikipedia.org/wiki/Rust_(programming_language)).
- Rust Foundation: [foundation.rust-lang.org](https://foundation.rust-lang.org).
- Rust source: [github.com/rust-lang/rust](https://github.com/rust-lang/rust).
