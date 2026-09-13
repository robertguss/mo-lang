---
title: "C — The Portable Assembler"
created: 2026-09-13
updated: 2026-09-13
type: research
tags: [history, languages]
sources:
  - "../raw/plang-history-2026-09/deep-dives/01_c.md"
---

### Headline

C is the "portable assembler" — designed by Dennis Ritchie at Bell Labs (1972–73) so Ken Thompson's team could rewrite Unix without giving up performance ([Ritchie, "The Development of the C Language"](https://www.cs.tufts.edu/~nr/cs257/archive/dennis-ritchie/chist.pdf)). Type safety "did not seem as important then as they became later" — Ritchie's own words.

### What C got right

- **A model of the machine, not of values.** Structs, arrays, and pointers map to bytes; there is no algebra of values sitting on top.
- **One-pass compilation.** Declarations must precede use because B's compiler had memory limits; C inherited the constraint, and it made compilers fast for decades.
- **Portable syscall boundary.** C won by being the language every OS ships with, and every FFI must ultimately speak.
- **K&R as reference.** The 1978 book *The C Programming Language* was the specification until ANSI arrived a decade later.

### What C got wrong

- **Undefined behavior surface.** Signed overflow, aliasing rules, sequence points — a minefield modern optimizers exploit aggressively.
- **Preprocessor is a second language.** Textual macros with no scoping — the root cause of the C++ template metaprogramming detour and half of the security CVEs in the ecosystem.
- **Null-terminated strings.** Every buffer overflow you have ever read about traces back here.
- **No modules.** Headers plus a linker; every large C project reinvents build hygiene.

### Why Mo cares

C is Mo's [[d24-compile-to-c-via-zig]] target — not because C is a good language but because it is the only truly universal ABI. The plan mirrors Zig's use of C as an intermediate: emit small, boring C, then let a portable C compiler (Zig's `cc`) handle codegen for every target. That inherits C's portability without inheriting its ergonomics.

Mo's rejection list is largely a rejection of C's defaults:

- No implicit conversions ([[d11-statically-typed]]).
- No null; use [[q05-option-and-no-nil]].
- No mutable-by-default; see [[d10-immutable-by-default]].
- No macros; metaprogramming is comptime evaluation in the manner of [[zig]].

### The lasting lesson

Ritchie's C won because it was *small enough to hold in your head* and *close enough to the machine to trust*. Every systems language since has re-argued the balance: Rust adds a proof system on top, Zig adds hygiene without a proof system, Go trades control for simplicity. Mo's answer is different again: keep C-level control at the edges via capabilities, but hide it behind a functional core that agents can generate without stepping on undefined behavior.

## Related

- [[zig]] — the modern attempt to be "more pragmatic than C"
- [[cpp]] — the "zero-overhead abstraction" road not taken
- [[rust]] — proof-carrying alternative to C's honor system
- [[d24-compile-to-c-via-zig]]
- [[d30-supply-chain-security]] — why Mo distrusts C's culture of implicit trust

## Sources

- [Full deep-dive](../raw/plang-history-2026-09/deep-dives/01_c.md)
- [Ritchie, "The Development of the C Language"](https://www.cs.tufts.edu/~nr/cs257/archive/dennis-ritchie/chist.pdf)
