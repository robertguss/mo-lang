---
title: "Step 13: the C backend, brief for the worker"
created: 2026-09-13
updated: 2026-09-13
type: plan
tags: [compiler, performance, runtime]
sources: [spec/design-v0/07-toolchain.md, directions/d24-compile-to-c-via-zig.md]
status: in-progress
---

# Step 13: the C backend

Chapter 7, build order item 2: C via the Zig toolchain for release, differential-tested against the interpreter, one dependency, a single static binary. This step does the smallest honest version: `mo build file.mo` emits C for the program's modules, compiles it with `zig cc`, and produces one binary that runs `main` on `Mo.Server`. Scope for this step is pure code plus the platform parts programs 2 and 3 use; processes under the compiled binary are allowed to fall back to "not yet: run it on the interpreter" with a clear error, recorded.

## Orientation

`toolchain/src/bytecode.zig` (the lowering the C emitter mirrors), `vm.zig` (the semantics to reproduce exactly: overflow traps, value semantics, contract checks at tier 2 off by default in release, on with `--contracts`), `server.zig`, `spec/design-v0/07-toolchain.md`, `directions/d24-compile-to-c-via-zig.md`, `d25-interpreter-for-the-edit-loop.md`.

## Write scope

`toolchain/` and `examples/`, branch `session-05`, one commit per part, push after every commit.

## Part A: the runtime in C

`toolchain/runtime/mo_rt.h` and `mo_rt.c`: values (tagged), strings, lists, maps, sets, the stdlib rows of `09-stdlib.md` that the interpreter implements, overflow-trapping arithmetic (`__builtin_*_overflow`), the crash report (same text as the interpreter's), and the `Mo.Server` platform parts (`args`, `env`, `stdout`, `stderr`, `fs` with the same containment rules, `clock`, `exit`). Memory: an arena per call frame with the same safe-point release the interpreter uses; no GC. One file each, C11, no dependencies.

## Part B: the emitter

`emit_c.zig`: from the checked tree (not the bytecode) to one C translation unit per program. Straightforward code: one C function per Mo function, structs as C structs, enums as tagged unions, `case` as switch, `for` as loops, combinators as loops, anonymous functions as static functions with an explicit environment. Contracts compiled in behind a runtime flag. Every emitted file must compile with `zig cc -std=c11 -Wall -Werror`.

## Part C: `mo build`

`mo build file.mo [-o name] [--contracts] [--target <zig triple>]` writes the C to `zig-out/mo-build/<name>/`, runs `zig cc` (found next to the running `mo` or on PATH; record how), and leaves a static binary. Cross-compilation is `--target`, nothing else.

## Part D: differential testing

`zig build test` gains: for every program in `examples/programs/` (multi-file included), `mo build` it and run the binary with the same `# run:` lines; stdout, stderr text of crash reports, and exit codes must equal the interpreter's. Every corpus module with tests: `mo build --tests` produces a binary that runs the module's tests and prints the same lines as `mo test`; compare. Any difference is a bug in one of the two, and the interpreter is the reference.

## Part E: numbers

Bench rows: `logstat-4k-c` (the compiled logstat over the same 4,000-line file), `build-logstat` (wall time of `mo build` for logstat, C emission and `zig cc` separately). Report the interpreter-to-native ratio and the overflow-check cost (build once with `-fwrapv` semantics for the comparison only, never shipped).

## Also

A read-only `Fs` passed as a parameter must be refused at check time (`MO0404`), not at run time: track `read_only` in the capability's type.

## Done when

Every program in the corpus builds and matches the interpreter, the numbers are recorded, pushed, decisions listed. If processes cannot be compiled in this step, the error is clear and the fact is in the final message.

## Related
- [[interpreter-step-12]]
- [[d24-compile-to-c-via-zig]]
- [[d25-interpreter-for-the-edit-loop]]
