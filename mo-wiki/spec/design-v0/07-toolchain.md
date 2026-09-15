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

- Perceus-style reuse without a GC: immutable inductive data cannot form cycles, `var` guarantees uniqueness in place. Koka, MoonBit, and Roc ship this. Session 5, step 21: measured on 100,000 updates of one var. `push`, map `set` and `remove`, and set `add` already wrote in place (a pushed list: 25 allocations as a binary); a field set and a string grown by interpolation now do too (a field set: 200,224 allocations to 7 under `mo run`, 200,076 to 5 as a binary; an append: 16.8 GB copied in 139 ms to 24 MB in 14 ms, and 6.8 GB in 189 ms to 2.4 MB in 6 ms as a binary). A map `set` still allocates once an update (the interpreter a call's arguments, the binary a map's header), and removing a map's oldest key again and again went from 29.0 s to 180 ms for 4,000 removes under `mo run` (12.6 s to 39 ms as a binary) once a write in place stopped being remembered once per remove.
- Each process gets its own heap region so a crash frees it whole. Hypothesis. Session 5, step 21: a process at rest costs 38.8 KiB under `mo run` and 22.7 KiB as a binary (73.2 and 39.9 KiB before step 21, when each held a thread), freeing one takes 2.0 µs in both, and a message's deep copy is 228 bytes a kv GET and 641 bytes a notes POST under `mo run`, 104 and 288 bytes as a binary, whose parcels reserve 12 KiB each.
- Processes on every core, since they share nothing (Session 5, step 30): a scheduler per core in both runtimes, a process on one scheduler for its life, and the runtime's tables behind one lock that a process's Mo code runs without, so updates on different schedulers run at the same time and each still begins and commits under the lock. A send to a process on another scheduler goes in under that lock and pokes the target's scheduler, which sleeps in its poller only after a moment without a poke. A sweep waits for every update in progress to park or end before it counts handles. `MO_CORES=1` is the one-thread runtime of step 29b.
- A checkable "allocates nothing, constant stack" property on chosen functions, in the `fip` style, run in tier 1. Later.
- Overflow checks cost a few percent on hot integer loops, to be recovered by contract-proved bound elision. Measured, not assumed. Session 5, step 21: `logstat-4k-c` against the same build with `-fwrapv`, -2.6% (9.43 and 9.68 ms, within the noise); contracts cost more than the checks: 41.5% on `logstat-4k-c` (6.67 ms without), 3.9% on `kv-10k-get-c`, 7.1% on 500 notes POSTs, and logstat's two `ensures !card?(...)` in `parse.mo`, a scan of every path's characters, are 12.2 and 11.7 points of it.
