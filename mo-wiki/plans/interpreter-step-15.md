---
title: "Step 15: processes and Net in the C backend, brief for the worker"
created: 2026-09-13
updated: 2026-09-13
type: plan
tags: [compiler, runtime, processes]
sources: [plans/interpreter-step-13.md, plans/interpreter-step-11.md, spec/design-v0/03-semantics.md]
status: done
---

# Step 15: processes and `Net` in the C backend

Step 13 refused to compile a program with processes or sockets. This step compiles them, so `kv` and `echo` become native binaries that behave exactly as they do under `mo run`, and the interpreter stays the reference.

## Orientation

`toolchain/runtime/` (the C runtime), `emit_c.zig`, `sim.zig` and `server.zig` (the scheduler, mailboxes, supervisors, `Net` over `std.Io`, the blocking-call design from step 11 part C), `spec/design-v0/03-semantics.md` (processes, failure), the process rows of the decision log (steps 4, 9, 11, 12).

## Write scope

`toolchain/` and `examples/`, branch `session-05`, one commit per part, push after every commit.

## Part A: the scheduler in C

Port the `Mo.Server` scheduler: processes as records with state, a bounded mailbox, and an `update` function pointer; run to quiescence driven by `main` and I/O; `send`, `ask` with deadlines, `start`, supervisors with restart limits, `update` as a transaction with in-place writes undone on crash, invariants after every update, the crash report text identical to the interpreter's. Deep copies between processes as the interpreter does.

## Part B: `Net` in C

`listen`, `accept`, `connect`, `read_line`, `write`, `close` over POSIX sockets with the same deadline outcomes as step 11 decided; blocking calls must not stop the scheduler: use the same approach the interpreter uses (a thread per blocked call is acceptable; record it), and keep `Conn` closing when its holder stops.

## Part C: `mo build` accepts them

Remove the refusal. `--tests` binaries run process tests in fixed order; `--sim` is not compiled (the simulator stays the interpreter's, record it). The differential test now builds `echo` and `kv` and every process corpus file and compares with the interpreter.

## Part D: numbers

Bench rows `kv-10k-get-c` and `echo-1k-c` through the native binaries; report native versus interpreted for both and the resident memory of native `kv` after 50k SETs.

## Done when

Green, `kv` and `echo` native and identical to the interpreter, rows recorded, pushed, decisions listed.

## Related
- [[interpreter-step-13]]
- [[interpreter-step-14]]
- [[program-3]]
