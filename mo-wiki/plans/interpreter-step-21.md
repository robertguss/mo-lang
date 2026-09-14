---
title: "Step 21: memory and green threads, brief for the worker"
created: 2026-09-13
updated: 2026-09-13
type: plan
tags: [runtime, performance, processes, tooling]
sources: [spec/design-v0/07-toolchain.md, plans/interpreter-step-20.md, plans/control-run-4.md, decisions/decision-log.md]
status: done
---

# Step 21: memory and green threads

Chapter 7 made four memory bets and measured none of them. Step 20 made the runtime the loop and left one number behind: a process is still an OS thread, so a process per connection holds 6,400 connections under `mo run` (230 KiB each, 1,476 MiB) and 5,536 as a binary (354 MiB) before the OS thread limit. Program 1, the job queue, wants a process per job and per connection. This step makes a process cheap, measures the bets, fixes round 4's one toolchain bug, and sharpens the three diagnostics round 4 tripped. Robert's call (13 Sep, night): no new syntax in this step; the one-line `if` stays a question for the morning.

## Orientation

`spec/design-v0/07-toolchain.md` (the bets), `03-semantics.md` (processes, the failure model), `toolchain/src/turns.zig` (a thread per process, the turns), `sim.zig`, `sources.zig`, `region.zig`, `vm.zig` (the 10,000-depth limit and the 256 MiB reserved stack per process), `runtime/mo_rt.c` (the same in C), `bench/results.tsv`, `plans/interpreter-step-20.md` (the numbers and the two bugs it found), `plans/control-run-4.md` (the four tooling loops), the decision-log rows of steps 19 and 20 and round 4.

## Write scope

`toolchain/`, `examples/`, and these spec lines only: the "Memory and performance bets" list of `07-toolchain.md` (each bet gains its measured number, nothing else changes), the `Fs.fixture` row of `09-stdlib.md` and `PRELUDE.md`; each with a "Session 5, step 21" line. No grammar change. Branch `session-05`, one commit per part, `Step 21 part X` in the subject, push after every commit, `zig build test` green at every commit.

## Part A: a process is not an OS thread

Both runtimes. An `update` runs to completion except where it waits (`ask`, `accept`, `read_line`, `write`, `Fs` calls with a deadline); a waiting process parks and costs no thread; a small pool of OS threads, or main's thread with the poller, runs whatever is runnable. `mo test` stays deterministic, `--sim` unchanged. The worker chooses the mechanism (stackful coroutines over `std.Io`, or an explicit continuation at each wait, or a state machine per `update`) and records why in the report. The rules of steps 19 and 20 hold unchanged: a finished process is freed, the held-send deadlock is a report, backpressure pauses a source at the bound, `platform.exit` stops a served listener. The 10,000-depth limit stays a Mo crash report; the stack a process costs at rest is the number that must fall.

The target: a process per connection is bounded by the OS's file descriptor limit, not by threads. Record the count of idle connections one `echo` process per connection holds under `mo run` and as a binary at the default `ulimit -n` and at `ulimit -n 65536`, with resident memory at each; the KiB a process costs at rest; and the step 19 reproduction (200,000 processes) still flat. Timeouts and a memory watchdog on every run; kill anything past 4 GB.

## Part B: the bets, measured

1. **In-place reuse.** Step 7 made `push` grow in place. Report which of these already run in place under `var` and make the rest do so where a value is uniquely held: map `put` and `delete`, struct field update, string append, `set` add. A bench row per shape (100k operations) before and after, both runtimes; allocations counted.
2. **A heap per process.** Already true (a region per process). Measure what it costs: KiB per process at rest, the time to free one, and the bytes a message deep-copies on `kv-10k-get` and on notes's POST. Report, do not redesign.
3. **The contract cost.** `logstat-4k-c` against `-nocontracts` today, and the same pair for `kv-10k-get-c` and a notes run, as a percentage; the three hottest contract sites by a profile. No elision work; if a fix under fifty lines removes ten points, take it and say so.
4. **Overflow checks.** `logstat-4k-c` against `-wrap`, the percentage, in the same table.

## Part C: `Fs.fixture()` refuses `..`

Round 4's bug: `Fs.fixture()` accepts a path with `..` where the real `Fs` refuses it. The fixture refuses it the same way, with the same error, both runtimes, a corpus test that shows a program staying inside its folder, the two spec rows.

## Part D: three diagnostics, no syntax

Each with a `rejects/` corpus file, the catalog's `why` text, and `zig build errors` regenerated:

1. `MO0101` at a one-line `if cond: a else: b`: the message shows the block form to write, as a fix candidate if the rewrite is unambiguous (confidence 100, so `mo fix` applies it).
2. `MO0101` at a variant matched by position, `Short(a, b)`: the message names the fields and the form `Short(by: n)`.
3. `MO0206` when a method call binds to a literal, `0..60.map`: the message says what the method bound to (`60`) and shows `(0..60).map`.

## Numbers

One table in the report: idle connections held (both runtimes, both limits) with memory; KiB per process at rest before and after; the 200,000-process reproduction; every bench row before and after, best of five, with any row over 10 percent slower explained; the reuse rows; the deep-copy bytes; the contract and overflow percentages.

## Done when

Green at every commit; a process per connection bounded by descriptors, not threads, in both runtimes; the four bets each with a number in chapter 7's list; `Fs.fixture()` refusing `..`; the three diagnostics with their corpus files; the numbers table; pushed; a numbered list "Decisions the brief did not cover".

## Result

Written in about two hours, four commits, green at each. A process is a stackful fiber on main's thread with a kqueue poller, in both runtimes. Idle connections, one echo process each, at `ulimit -n 65536`: 8,026 then out of memory at 1.89 GiB → 65,530 at 2.41 GiB under `mo run`; 8,185 then out of memory at 486 MiB → 65,530 at 1.64 GiB as a binary; 65,530 is the descriptor limit less the standard streams, two listeners, and the poller. A process at rest: 73.2 → 38.8 KiB interpreted, 39.9 → 22.7 KiB native; the 200,000-process reproduction flat at 23 and 12.5 MiB; freeing one 2.0 µs. Bench, best of five: no row over 10 percent slower; echo-1k 57.1 → 18.3 ms, echo-1k-c 59.0 → 25.0, kv-10k-get 458 → 409, kv-10k-get-c 386 → 210, http-1k 90.0 → 57.9, http-1k-c 62.6 → 55.9. The bets: a field set and a string append now write in place (200,224 → 7 allocations; 16.8 GB copied → 24 MB); a message deep-copies 228 bytes on a kv GET and 641 on a notes POST interpreted, 104 and 288 native; contracts cost 41.5 percent on logstat native by the worker's harness and 22.4 by the bench, 3.9 on kv, 7.1 on notes; overflow checks within noise. `Fs.fixture()` refuses `..`; the three diagnostics with corpus files, and `mo fix` rewrites a one-line `if`. Fable's probes: the three diagnostics on files the brief did not name, 20,000-deep recursion a Mo report in both runtimes, 200 idle connections never delaying a live request, and one finding: an HTTP acceptor stops accepting at about 1,000 request-less connections, its mailbox bound, where kv over raw `Net` holds 3,000 (a decision-log row, flagged for program 1). Unmet: the Linux epoll path compiles and was never run.

## Related
- [[interpreter-step-20]]
- [[control-run-4]]
- [[research-agenda-2026-09-response]]
- [[roadmap]]
