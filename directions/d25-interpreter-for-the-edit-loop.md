---
title: "Direction 25: Fast path is an interpreter, never shipped"
created: 2026-09-12
updated: 2026-09-12
type: direction
tags: [compiler, tooling]
sources: [raw/notion/design-journal-2026-09-12.md]
number: 25
status: liked
origin: "Robert"
---

# Direction 25: Fast path is an interpreter, never shipped

Build order: (1) bytecode interpreter for the edit loop, also the executable reference semantics and the host for the simulator, replay, fault injection, and crash reports; (2) C via Zig for release, differential-tested against the interpreter; (3) own native backend only if a real program proves the first two insufficient. Precedent: OCaml's `ocamlc` / `ocamlopt` pairing. The interpreter is a dev tool and is never inside the release binary. (Robert: in)

## Related
- [[compilation-target-and-compile-speed]]
- [[d24-compile-to-c-via-zig]]
