---
title: "Go — The Anti-C++ from Google"
created: 2026-09-13
updated: 2026-09-13
type: research
tags: [history, languages]
sources:
  - "../raw/plang-history-2026-09/deep-dives/11_go.md"
---

### Headline

Robert Griesemer, Rob Pike, and Ken Thompson designed Go at Google (2007) around a "shared dislike of C++" ([Wikipedia: Go](https://en.wikipedia.org/wiki/Go_(programming_language))). Public announcement November 2009; Go 1.0 in March 2012. Explosion in adoption came with Docker (2013) and Kubernetes (2014).

### The three ideas that shaped everything

- **Simplicity as a religion.** ~50-page spec. No inheritance, no generics (until 1.18, ten years in), no exceptions, no operator overloading. "Less is exponentially more" (Pike, 2012).
- **Goroutines and channels.** Lightweight threads + CSP-style channels as language primitives, backed by a runtime scheduler. Concurrency as a first-class syntactic feature.
- **Compile-fast.** Whole-program compilation; deliberately simple type system to keep parsing cheap. Feel like a scripting language, ship like a static binary.

### What Go got right

- **`gofmt`.** One canonical format, no debate, always applied. Every language after Go steals this.
- **Static binaries.** No runtime dependencies. Kubernetes lives.
- **Standard library.** `net/http`, `encoding/json`, `context`, `database/sql`, `crypto` all in stdlib. You can build a service with zero dependencies.
- **Compatibility promise.** Go 1.0 code still compiles under Go 1.22+. The single most user-friendly thing a language can promise.
- **Interfaces (structural).** Duck typing done statically. Small interfaces (`io.Reader`) compose beautifully.

### What Go got wrong (mostly by omission, then fixed)

- **No generics until 1.18 (2022).** Ten years of `interface{}` and code generation.
- **Nil pointers.** Kept from C. `panic: runtime error: invalid memory address or nil pointer dereference`.
- **Error handling by convention.** `if err != nil { return err }` fifteen times per function. Explicit, but relentless.
- **GC latency for tail applications.** Go's concurrent GC is world-class, but there is a runtime cost Rust and Zig avoid.

### What Mo takes

- **Simplicity as a governor.** Every feature is asked to justify its complexity. Mo aims for a spec small enough to fit in an agent's context window.
- **`gofmt`-style enforced formatting.** [[d04-style-rules-become-laws]] — style rules become laws, applied by the toolchain.
- **CSP-flavored concurrency at the edges.** [[d12-concurrency-at-the-edges]] — channels + goroutines as inspiration, but wrapped in structured-concurrency semantics.
- **Fast compile as a design constraint.** Interpreter for edit loop, C via Zig for release ([[d24-compile-to-c-via-zig]]).

### What Mo refuses

- **Nil.** [[q05-option-and-no-nil]].
- **Error-as-convention.** Errors as values with typed `Result`, à la Rust ([[rust]]).
- **Mutable by default.** [[d10-immutable-by-default]].
- **A GC as language default.** Mo aims for capability-declared regions and RAII-style resource management.

### The lasting lesson

Go proved that **"simple, boring, and shippable"** beats "expressive, elegant, and clever" for infrastructure software at scale. The Docker/Kubernetes ecosystem exists because Go removed enough choices that competing implementations converge. Mo takes the same posture toward the *shape* of programs while pushing further on safety and verification.

Rob Pike, 2012: "The key point here is our programmers are Googlers, they're not researchers." Mo's key point: our programmers are agents.

## Related

- [[cpp]] — the language Go was designed to replace
- [[rust]] — the other post-C++ answer, on a different axis
- [[zig]] — the other "simple, boring" bet
- [[d04-style-rules-become-laws]]
- [[d12-concurrency-at-the-edges]]

## Sources

- [Full deep-dive](../raw/plang-history-2026-09/deep-dives/11_go.md)
- [Wikipedia: Go](https://en.wikipedia.org/wiki/Go_(programming_language))
- [Pike, "Go at Google: Language Design in the Service of Software Engineering"](https://go.dev/talks/2012/splash.article)
