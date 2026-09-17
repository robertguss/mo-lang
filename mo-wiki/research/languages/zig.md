---
title: "Zig — More Pragmatic Than C"
created: 2026-09-13
updated: 2026-09-17
type: research
tags: [history, languages]
sources:
  - "../../raw/plang-history-2026-09/deep-dives/14_zig.md"
---
# Zig — More Pragmatic Than C


## Headline

Andrew Kelley created Zig in 2015 with a single stated aim: **"more pragmatic than C"** ([Andrew Kelley, Intro to Zig](https://andrewkelley.me/post/intro-to-zig.html)). Started 2015; 0.1.0 released February 2017 (corrected 17 Sep 2026). Zig Software Foundation (501(c)(3)) founded 2020. Zig 0.10 (November 2022) shipped the self-hosted compiler.

## The three ideas that shaped everything

- **No hidden control flow, no hidden allocations.** Every function call is a function call; every allocation is explicit and takes an `Allocator` argument. What you see is what you get.
- **`comptime` as the metaprogramming story.** Compile-time evaluation with the *same* language as runtime. Replaces the preprocessor, replaces macros, replaces generics all in one primitive.
- **Zig as a C toolchain.** `zig cc`, `zig c++`, `zig build` are drop-in replacements for the traditional C/C++ compilers, with painless cross-compilation. Zig is a better C compiler than most C compilers even for pure-C projects.

## What Zig got right

- **Explicit allocators.** Every allocation is threaded through an allocator, which the caller supplies. Testing memory failure paths becomes trivial.
- **Cross-compilation for free.** `zig build -Dtarget=aarch64-linux` just works. This alone justifies Zig's existence.
- **Error unions (`!T`).** Errors are values in the return type; no exceptions, no unchecked returns. Enforced with `try` and `catch`.
- **Debug vs release modes with distinct semantics.** Runtime safety checks in Debug/ReleaseSafe, optimized-out in ReleaseFast, small-code in ReleaseSmall. Undefined behavior is a *tool*, not a footgun.
- **Package manager (2023+).** Content-addressed, no central registry required.

## What Zig is still working out

- **Async model.** The 2025 redesign around a new `Io` interface ([HN discussion](https://news.ycombinator.com/item?id=44545949)) is ongoing.
- **Backend maturity.** Custom x86_64/arm64 backends are new; LLVM is still the release path.
- **Documentation.** Language spec has lagged the implementation.

## What Mo takes — a lot

Zig is Mo's closest sibling on the implementation side.

- **[[d24-compile-to-c-via-zig]].** Mo emits C, then compiles it with `zig cc`. Free cross-compilation, tiny toolchain footprint.
- **[[d34-packages-are-recipes]].** Content-addressed packages with declared capabilities, inspired by Zig's package model but with capability manifests on top.
- **`comptime` metaprogramming.** Typed compile-time evaluation instead of macros or templates.
- **Explicit allocators.** Effect capabilities include memory-allocation capabilities; runtime is not implicit.
- **Debug/Release mode distinction.** Mo's build modes extend the pattern: interpreter → checked C → optimized C.

  17 Sep 2026: [[q08-verification-tiers|Q8]]'s tiers are not these — they are instant, fast, and background.

## What Mo refuses

- **Manual memory management as default.** Regions + capabilities do the ownership work (17 Sep 2026: Mo has no RAII and no destructors — a per-process region, chapter 7); Mo does not ask agents to reason about lifetimes as carefully as Zig does.
- **Undefined behavior as an optimization tool.** Mo prefers checked semantics with capability-guarded escape hatches.

## The lasting lesson

Zig proves you can compete with C on C's home turf by **being uncompromising about what C got wrong** (macros, headers, undefined behavior, cross-compilation) *while refusing to add a proof system*. Mo agrees on the tooling story and disagrees on the type story — Mo wants the proof system Rust has, delivered through capabilities and refinements ([[d22-rust-plus-refinements-types]]).

Kelley's rule: pragmatic first, safe second, elegant third. Mo's rule: pragmatic *and* safe, both first, elegant when possible.

## Sources

- [Full deep-dive](../../raw/plang-history-2026-09/deep-dives/14_zig.md)
- [Andrew Kelley, "Introduction to the Zig Programming Language"](https://andrewkelley.me/post/intro-to-zig.html)
- [kristoff.it, "Zig: self-hosted"](https://kristoff.it/blog/zig-self-hosted-now-what/)

## Related

- [[c]] — the target
- [[rust]] — the other post-C systems language
- [[go-history]] — the "simple stack" competitor
- [[d24-compile-to-c-via-zig]]
- [[d34-packages-are-recipes]]
- [[q13-implementation-language]]
