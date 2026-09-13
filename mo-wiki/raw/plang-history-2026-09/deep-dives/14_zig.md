# Zig — More Pragmatic Than C

## Origin story

### Designer, institution, year

Zig was created by **Andrew Kelley**. The project began in **2015**, first version released **February 8, 2016**. Kelley "took a break from working on **Genesis Digital Audio Workstation** to create a new programming language" ([Andrew Kelley, Intro to Zig](https://andrewkelley.me/post/intro-to-zig.html)).

Kelley formalized Zig's stewardship in **2020** by founding the **Zig Software Foundation** (ZSF), a 501(c)(3) nonprofit that now employs several core developers.

Milestones:
- **February 8, 2016** — First public release (0.1.0).
- **2018** — Zig's C compiler backend and C-interop demonstrated.
- **2020** — Zig Software Foundation founded.
- **Nov 1, 2022** — Zig 0.10.0 shipped the new self-hosted compiler ([kristoff.it, "Zig: self-hosted"](https://kristoff.it/blog/zig-self-hosted-now-what/)).
- **2023–2024** — Custom (non-LLVM) x86_64 and arm64 backends; incremental compilation experiments.
- **2025** — Redesign of Zig's async model around a new `Io` interface ([HN discussion 44545949](https://news.ycombinator.com/item?id=44545949)).

### The motivating problem

Kelley's goal: "**more pragmatic than C**" ([Andrew Kelley](https://andrewkelley.me/post/intro-to-zig.html)). Concrete pain points he wanted to address:
- C's macro preprocessor is a separate, second-class language.
- C's undefined behavior surface is huge and unnoticed.
- C doesn't distinguish debug and release modes cleanly.
- C's build system fragmentation (make, autotools, cmake) is a mess.
- Cross-compilation in C is painful.

Zig's stated priorities:

> 1. **Pragmatic**: Whether the language helped users accomplish what they were trying to do better than any other language.
> 2. **Optimal**: The most natural way to write a program should result in top-of-the-line runtime performance, equivalent to or better than C.
> 3. **Safe**: Safety should accompany optimality without taking the driver's seat.
> 4. **Readable**: Zig prioritizes reading code over writing it, avoids complicated syntax, and generally aims to provide a canonical way to do everything.

([Andrew Kelley](https://andrewkelley.me/post/intro-to-zig.html))

### Initial reception

Slow build, then a cult following. Zig gained mainstream visibility around 2020–2022 through:
- **Bun** (Jarred Sumner), a JavaScript runtime written in Zig, launched 2022.
- **`zig cc`** as a drop-in Clang wrapper — used as a portable cross-compiler by Uber, TigerBeetle, and many CI pipelines.
- **TigerBeetle**, a financial-transaction database entirely in Zig.

Zig has never had a 1.0 release; the pre-1.0 stability policy allows breaking changes each release.

## Design philosophy

### Core principles

- **No hidden control flow.** No exceptions, no operator overloading, no property accessors. If you see `foo(bar)`, no other functions run.
- **No hidden memory allocations.** All allocation is explicit through allocator parameters. The stdlib takes allocators; e.g., `std.ArrayList(u8).init(allocator)`.
- **`comptime`** as the metaprogramming and generics mechanism. Types are first-class compile-time values.
- **Manual memory management** with `defer` and `errdefer`.
- **Cross-compilation as first-class** — `zig build -Dtarget=aarch64-linux-gnu` just works, because Zig ships libc headers and glibc/musl stubs for many targets.
- **Debug and release modes with different semantics.** Debug catches undefined behavior; release trades safety for speed ([Andrew Kelley](https://andrewkelley.me/post/intro-to-zig.html)).

### Build modes

Zig has four:
- **Debug** — fast compile, slow runtime, undefined behavior traps.
- **ReleaseSafe** — slow compile, fast runtime, safety checks retained.
- **ReleaseFast** — fastest runtime, minimal safety.
- **ReleaseSmall** — optimized for binary size.

The mode is available in source: `@import("builtin").mode`.

### What Zig rejected

- **A macro preprocessor.** Comptime replaces it.
- **Exceptions.** Error unions instead.
- **Hidden allocations.** No allocation without an allocator parameter.
- **A garbage collector.**
- **Operator overloading.**
- **Traditional generics syntax.** Types are `comptime` values.

### Cultural values

Small and comprehensible; skeptical of complexity; anti-hype; Zig Software Foundation avoids VC funding and grows on donations.

## Language features

### Syntax

C-ish braces; type annotations; explicit pointers (`*T`, `[*]T`, `[]T`); slices, arrays, tuples; unions; errors as first-class values.

### Type system

Static; strong; type inference for locals; nominal for structs, unions, enums; **types are first-class comptime values** — the mechanism for generics and metaprogramming. "Types are first-class citizens: They can be assigned to variables. They can be passed as parameters to functions. They can be returned from functions. They can only be used in expressions known at compile time" ([Ziglang docs 0.7.0](https://ziglang.org/documentation/0.7.0/)).

**Comptime** is Zig's signature: "A `comptime` parameter means: At the call site, the value must be known at compile time, or compilation fails… Compile-time parameters are how Zig implements generics. This is described as compile-time duck typing." "String formatting is implemented in userland using compile-time evaluation, `comptime` variables, `inline for`, and `@compileError`; it is not hard-coded into the Zig compiler" ([Ziglang docs 0.7.0](https://ziglang.org/documentation/0.7.0/)).

### Memory model

Manual with explicit allocators. No GC. `defer` for scope-based cleanup; `errdefer` for cleanup only on error paths. Debug builds ship a `GeneralPurposeAllocator` that detects leaks, double-frees, and use-after-free.

### Concurrency

Historically async/await with stackless coroutines. In 2020–2022 the self-hosted compiler had not implemented async ([ziggit forum: async not implemented](https://ziggit.dev/t/async-has-not-been-implemented-in-the-self-hosted-compiler-yet/8360)).

In **2025** the design was overhauled around an **`Io` interface** ([HN 44545949](https://news.ycombinator.com/item?id=44545949)). Rather than red/blue functions, the design passes an `Io` handle explicitly, similar to how allocators are passed. From the discussion:

- "Zig no longer has `async`/`sync`/red/blue functions, but now has **IO and non-IO functions**. IO functions require access to an `Io`; non-IO functions do not."
- "It is rare for a function to unexpectedly gain a dependency on 'doing IO' in general. Most of a Zig codebase will have access to an `Io`; only leaf functions doing pure computation will not."
- kristoff_it: "Async keywords statically color a function red, preventing code reuse between sync and async versions. Using async/await automatically opts code into stackless coroutines, with no way to prevent that."
- The `Io` design "abstracts usage from implementation well, unlike Rust." ([HN 44545949](https://news.ycombinator.com/item?id=44545949))

Critics point out that this is still a form of function coloring (IO vs non-IO), just less viral than red/blue.

### Error handling

**Error unions** — a type-level construct combining an error set with a value type ([Andrew Kelley](https://andrewkelley.me/post/intro-to-zig.html)):

```zig
const FileOpenError = error { FileNotFound, OutOfMemory, UnexpectedToken };
pub fn parseU64(buf: []const u8, radix: u8) ParseError!u64 { ... }
```

Handling options ([Ziglang docs 0.7.0](https://ziglang.org/documentation/0.7.0/)):
- `try expr` propagates the error.
- `expr catch default` supplies a default.
- `expr catch |err| { ... }` handles named error.
- `expr catch unreachable` asserts errors are impossible (panic in debug/ReleaseSafe, UB in ReleaseFast).
- `if (result) |value| { ... } else |err| { ... }` matches success and failure.

"If `parseU64` is changed to return a different set of errors, Zig emits compile errors for: Handling impossible error codes, Failing to handle possible error codes" ([Andrew Kelley](https://andrewkelley.me/post/intro-to-zig.html)) — exhaustive error checking.

### Metaprogramming

Comptime is the entire metaprogramming story. Types, values, and functions all evaluate at compile time when needed. `inline for` unrolls loops. `@Type`, `@typeInfo`, `@TypeOf`, `@compileError`, `@compileLog` provide compile-time reflection.

### Module system

Files are structs. `@import("path.zig")` returns the top-level struct of that file. Since Zig 0.11 (2023) an **official package manager** ships with the compiler ([kristoff.it](https://kristoff.it/blog/zig-self-hosted-now-what/)).

### Notable innovations

- **Comptime** as a unified replacement for macros, generics, and const evaluation.
- **`zig cc`** — a Clang-compatible cross-compiler.
- **Error sets** with implicit inference (`!void` uses inferred set).
- **Debug traps for undefined behavior** in debug mode.
- **`defer` and `errdefer`** modeled on Go's `defer` but with error-path variant.

## Implementation

### Reference compiler

**Self-hosted Zig compiler** — written in Zig, LLVM backend for release, with new custom backends for debug speed. "Zig's new self-hosted compiler was scheduled to ship with the upcoming Zig 0.10.0 release on **November 1, 2022**" ([kristoff.it](https://kristoff.it/blog/zig-self-hosted-now-what/)).

Notable achievements:
- "The self-hosted compiler reduces memory usage by **3×** compared with the bootstrap compiler. Building the compiler itself: Previously required 9.6 GB of RAM. Now requires 2.8 GB of RAM" — using "data-oriented programming techniques."
- "Zig can now be built: On 32-bit systems. On machines with limited resources, including CI runners."

### Lexer, parser, IR, backend

Hand-written lexer/parser. AST → AIR (Analyzed IR) → LLVM IR (default) or custom backends (arm64, x86_64, C source, WebAssembly). The **C backend** produces C source code — "The C backend was intended to: Help replace the old bootstrap compiler implementation. Allow Zig to target architectures not supported by LLVM. Support architectures that require a specific C compiler, including certain game-console platforms" ([kristoff.it](https://kristoff.it/blog/zig-self-hosted-now-what/)).

Custom backends aim at:
- **Incremental compilation.**
- **In-place binary patching.**
- **Sub-millisecond incremental rebuilds** of arbitrarily large codebases ([kristoff.it](https://kristoff.it/blog/zig-self-hosted-now-what/)).

### Runtime

Very small — essentially the panic handler and thread startup. No GC.

### Bootstrapping

The bootstrap chain uses the C backend and a small C++ stage-0 (being phased out); Zig itself is written in Zig.

### Alternative implementations

The only production implementation. `zig cc` wraps LLVM's Clang as a cross-compiler.

## Ecosystem

### Package manager

Since 0.11 (2023), the official package manager is built into `zig build`. "The package manager would be part of the compiler rather than a separate executable. The stated rationale was that Zig is a language and a compiler toolchain. The package manager would not assume a central package index. The project did not plan to create an official package index. Version resolution would be similar to **Go's Minimal Version Selection**" ([kristoff.it](https://kristoff.it/blog/zig-self-hosted-now-what/)).

Decentralized: packages are fetched by URL, verified by hash, cached locally.

### Standard library

Growing rapidly: `std.mem`, `std.ArrayList`, `std.HashMap`, `std.fs`, `std.net`, `std.crypto`, `std.debug`, `std.testing`, `std.json`, `std.http`, `std.compress`. Allocator-parameterized throughout.

### Tooling

`zig build` — build system, test runner, cross-compiler, package manager. **ZLS** — Zig Language Server. **`zig fmt`** — formatter. **`zig cc`** and **`zig c++`** — Clang wrappers. **`zig translate-c`** — automatic C-to-Zig translator.

### Governance

**Zig Software Foundation** (ZSF) — 501(c)(3), funded by donations and corporate sponsors (Uber, Tigris, Bun, others). Andrew Kelley is BDFL; core team includes Loris Cro, Jakub Konka, and others.

## Adoption

### Where Zig has landed

- **Bun** — JavaScript runtime; heavy Zig codebase; possibly the highest-profile Zig project.
- **TigerBeetle** — financial-transaction database; entirely Zig; extreme performance and reliability claims.
- **`zig cc` as portable cross-compiler** — Uber has used it for building large C/C++ codebases; the community uses it to cross-compile Go, Rust, and C projects easily.
- **Ghostty** (Mitchell Hashimoto) — GPU-accelerated terminal emulator; heavily uses Zig.
- **RoadRunner-adjacent PHP FFI**, various embedded projects, game-engine cores, WebAssembly compilers.

### Where Zig hasn't broken through

- **Application software** — few major applications yet.
- **Enterprise backends** — the ecosystem is still too young.
- **Data science / ML.**
- **Web frontend.**

### Current momentum (2026)

Strong upward. Pre-1.0 uncertainty keeps some organizations out, but the trajectory — incremental compilation, custom backends, `Io` redesign, growing package ecosystem — is compelling. Kelley has publicly targeted 1.0 for after incremental rebuilds are shipped and the async story is stabilized.

## Criticism and open problems

- **No 1.0 yet.** Language and stdlib still break between releases; risky for production.
- **The `Io` redesign** is contentious; some argue it still colors functions.
- **Async ergonomics** are in flux.
- **Small ecosystem** — third-party libraries are limited.
- **Manual memory management** — leaks and use-after-free are less catastrophic than C thanks to debug tooling, but the language does not enforce safety like Rust.
- **Doubly-linked lists, graph structures, and self-referential data** are also awkward here — though for different reasons than Rust.
- **Documentation** — some parts under-documented; `ZLS` and automatic docs still maturing.

## Influence on other languages

- Zig has *influenced* mainstream thinking on:
  - The "no hidden control flow" principle.
  - Explicit-allocator patterns being adopted in Rust's `no_std` and even some Go RFCs.
  - Comptime as an alternative to macros.
- **Bun** has demonstrated that Zig can produce substantial application software.
- The Zig community has become vocal in the general "systems languages after C" conversation, alongside Rust and Odin.

## Key sources

- Andrew Kelley, ["Introduction to the Zig Programming Language"](https://andrewkelley.me/post/intro-to-zig.html) (2016).
- Andrew Kelley, keynote talks at Software You Can Love conferences (2018–).
- [Ziglang documentation](https://ziglang.org/documentation/0.7.0/) (0.7.0 archived; current at ziglang.org/documentation/master).
- Loris Cro, ["Zig: self-hosted now what?"](https://kristoff.it/blog/zig-self-hosted-now-what/), 2022.
- [Hacker News discussion 44545949](https://news.ycombinator.com/item?id=44545949) — Zig's new `Io`-interface async design (2025).
- [Ziggit forum: async not implemented](https://ziggit.dev/t/async-has-not-been-implemented-in-the-self-hosted-compiler-yet/8360).
- Zig Software Foundation: [ziglang.org/zsf](https://ziglang.org/zsf).
- Zig source: [github.com/ziglang/zig](https://github.com/ziglang/zig).
