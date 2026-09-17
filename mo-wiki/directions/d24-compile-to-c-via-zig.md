---
title: "Direction 24: Compilation target: C via the Zig toolchain for release, own fast backend for the edit loop"
created: 2026-09-12
updated: 2026-09-17
type: direction
tags: [compiler, runtime]
sources: [raw/notion/design-journal-2026-09-12.md]
number: 24
status: liked
origin: "Robert"
---

# Direction 24: Compilation target: C via the Zig toolchain for release, own fast backend for the edit loop

Zig toolchain as the only dependency (Tiger Style), trivial cross-compilation and static linking. LLVM deferred until performance demands it. Compile-to-Rust rejected as a trap (semantics mismatch). WASM deferred. Own VM off the table. (Robert agrees with Claude's recommendation, with the speed requirement added.) Superseded in framing by [[d36-vm-first-runtime]]: the VM is the reference runtime, the C backend compiles it ahead of time.

## Related
- [[d36-vm-first-runtime]]
- [[compilation-target-and-compile-speed]]
- [[q13-implementation-language]]
- [[d08-beam-qualities-without-the-beam]]
