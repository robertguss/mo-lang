# 7. Toolchain

## Build order

1. **Interpreter first.** A bytecode interpreter in Zig for the edit loop. It is also the executable reference semantics, and the host for the simulator, replay, fault injection, and crash reports. It is a dev tool and never ships inside a release binary.
2. **C via the Zig toolchain for release.** Differential-tested against the interpreter. Zig is also the C cross-compiler, so the whole build has exactly one dependency. Static linking, trivial cross-compilation, single binary.
3. **A native backend only if a real program proves the first two insufficient.**

Precedent: OCaml's `ocamlc` / `ocamlopt`. Warning taken from Bosque: don't build the language, the verifier, and the runtime at once.

## Compile speed

Compile time is the latency of the agent's loop. Targets: under 50 ms for tier 1 incremental, under 100 ms per changed function for tier 2. Pointer-free, index-based compiler data with a memcpy-speed disk cache from the first commit. Test, property, and proof results cached by declaration hash plus callee contract hashes, never invalidated. The toolchain's own incremental build time is tracked from the first commit, because the "100x faster" figure Zig was chosen on is not yet available on stable Zig.

## The agent interface is the toolchain

- Every declaration has a stable ID in a toolchain-owned sidecar (`.mo.ids`); source stays plain text. Tools expose `edit(id, source)`, `rename(id, name)`, `insert --after`, `delete`, with optimistic concurrency by hash. Edits are parsed before applying and rejected whole if broken. Text editing stays as the fallback.
- An MCP server over edit-by-ID, diagnostics, and history. No Mo-specific agent; any agent uses the tools.
- Version-pinned guidance served by `mo` itself, so a model that has never seen Mo gets the rules, the error catalog, and the idioms from the toolchain, not from training data.
- `mo fix` from day one: every language change ships with a rewriter, and every published package version carries an old-hash to new-hash patch.
- The spec-altitude view: exposed signatures, contracts, tests, and the `verified:` line, rendered as a document. A shape diff between versions is what a human reviews.

## Memory and performance bets

- Perceus-style reuse without a GC: immutable inductive data cannot form cycles, `var` guarantees uniqueness in place. Koka, MoonBit, and Roc ship this.
- Each process gets its own heap region so a crash frees it whole. Hypothesis.
- A checkable "allocates nothing, constant stack" property on chosen functions, in the `fip` style, run in tier 1. Later.
- Overflow checks cost a few percent on hot integer loops, to be recovered by contract-proved bound elision. Measured, not assumed.
