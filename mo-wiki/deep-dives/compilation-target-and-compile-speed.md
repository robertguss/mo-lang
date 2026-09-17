---
title: "Compilation target and compile speed"
created: 2026-09-12
updated: 2026-09-17
type: deep-dive
tags: [compiler, performance, runtime]
sources: [raw/notion/design-journal-2026-09-12.md]
---

# Compilation target and compile speed

### Target options weighed
1. **Native via LLVM** (Roc, Rust): full control, best perf; huge dependency, slow, we own the whole runtime.
2. **Compile to C** (Koka): no-GC native binary with any C compiler; Zig `cc` for painless cross-compilation; easy to debug output. Leaky for green threads but Koka and Erlang's runtime prove it works. **Chosen for release.**
3. **Compile to Rust:** tempting for Verus/Aeneas verification, but our semantics (value semantics, Perceus) fight the borrow checker and generated-Rust-that-doesn't-compile is a nightmare. **A trap.**
4. **WebAssembly first:** sandboxing fits capabilities; not yet a home for green threads or native single binaries. Later.
5. **Own bytecode VM:** the BEAM route. Off the table.

17 Sep 2026: reversed — Mo's bytecode VM is the reference runtime, with the C backend checked against it ([[d36-vm-first-runtime|d36]]).
Verification path is independent of target: SMT (Z3) talks to the compiler's own IR.
### Why Rust is slow (all design decisions, all avoidable)
Monomorphization per concrete type; trait solver + borrow checker before codegen; proc macros run arbitrary code; crate as compilation unit; LLVM even on debug builds. Rust's 2026 roadmap fights all five for single-digit wins.
### Evidence it can be different
- Roc rewrote 300K lines from Rust to Zig: incremental rebuilds 3.4s → 35ms (~100x), but only on a Zig nightly on x86-64; the stable toolchain was 8.6 s (qualifier added 17 Sep 2026, from [[roc]]).
- Zig: own x86 backend for debug builds (no LLVM), in-place incremental binary patching, sub-300ms rebuilds with C sources.
- Unison: content-addressed functions compiled once per hash; test results cached by hash, never re-run unless a dependency changed.
### Levers for Mo (most already held)
- **Two backends, one per loop.** Interpreter for the agent's iteration loop; C via Zig for release. **Decided: interpreter** (see below).
### Interpreter vs own native backend (Robert: interpreter)
|  | Own machine-code backend (Zig-style) | Interpreter (OCaml-style) |
|---|---|---|
| Build effort | Hardest thing on the project: regalloc, calling conventions, debug info, green-thread stack switching, per architecture. Zig took years. | Weeks. Portable everywhere for free. |
| Compile latency | Low | Near zero (no codegen) |
| Runtime speed | Near release | 10-50x slower |
| Simulation / replay / fault injection / crash reports | Must be compiled into machine code | Hooks in the interpreter loop; interpreter-native |
| Semantics | One implementation | Two, but the interpreter is the executable spec and the C backend is differential-tested against it |
| Ships? | Yes | Never. Release is native via C. |
**Why interpreter:** everything distinctive about Mo lives in the agent-compiler loop, and all of it is interpreter-native. The one loss, test runtime, has a second answer: content-addressed compilation makes the cached C build the fast native path (a C compiler at -O0 handles one small function in tens of ms), so a hand-written backend may never be needed.
- **Spec altitude = interface file.** Signature/contract/effects declared up front, so a body edit never recompiles dependents; only signature or contract changes ripple. OCaml `.mli`, free from the two-altitude design.
- **Content-addressed functions.** Semantic IDs become content hashes; compile once per hash; cache shared across all agents, so parallel agents never rebuild each other's work.
- **Tests cached by hash.** Pure-unless-capability + deterministic simulator = test results are a pure function of the code hash. Run only what changed.
- **No macros, no deep trait solving, small grammar.** Rust's three heaviest front-end costs don't exist. Dictionary passing for generics in debug builds to avoid code explosion.
- **Verification never blocks the loop.** Refinements and `never` clauses runtime-checked instantly; SMT proving runs in the background, cached by hash, upgrades the verification level on success. An agent never waits on Z3.
- **Compile-speed law.** Benchmark suite tracks build time per KLOC and incremental latency; a regression fails the build.
**Targets (held loosely):** incremental rebuild \< 50ms; full build of 100K lines in seconds; single-function test loop \< 100ms.
Sources: [Roc Rust-to-Zig rewrite](https://rtfeldman.com/rust-to-zig), [Zig self-hosted x86 backend default in debug](https://ziggit.dev/t/self-hosted-x86-backend-is-now-default-in-debug-mode/10447), [Unison: the big idea](https://www.unison-lang.org/docs/the-big-idea/), [Rust Fast Builds roadmap 2026](https://rust-lang.github.io/rust-project-goals/2026/roadmap-fast-builds.html)

## Related
- [[d23-compile-speed-first-class]]
- [[d24-compile-to-c-via-zig]]
- [[d25-interpreter-for-the-edit-loop]]
