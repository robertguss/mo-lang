---
title: "Step 34: placement, so the Mac's cores stop costing"
created: 2026-09-16
updated: 2026-09-16
type: plan
tags: [runtime, performance, processes]
sources: [plans/interpreter-step-30.md, plans/mac-scaling-run.md, plans/interpreter-step-31.md, spec/design-v0/03-semantics.md, spec/design-v0/07-toolchain.md]
status: in-progress (paused after part A, 16 Sep 15:45; parts B and C need the Mac)
---

# Step 34: placement, so the Mac's cores stop costing

Step 30 put a scheduler on every core and placed each new process on the scheduler with the fewest live processes ([[interpreter-step-30]]). On the VM's four cores that bought 3.7× on CPU-bound work and nothing on the queue, which is fsync-bound there. On the Mac's fourteen cores ([[mac-scaling-run]]) every row is fastest at one core and slower with each core added: the queue 2,908 pairs a second at 1 core against 2,416 at 14, `echo-1k` 19 ms against 104, `kv-10k-get` 383 ms against 1,236. Step 30's own row says why: an ask across schedulers costs 3.4× one on the same scheduler (100k asks 0.05 s on one scheduler, 0.17 on two), and every program's request path crosses, since the acceptor, the worker it starts, and the store it asks land on different schedulers by the fewest-live rule. Step 31 added a second row: under `mo run` at 128 askers holding asks, the deferred reply runs at 0.46 of the send shape, 128 fibers parked in `turns.ask` each woken through `answers[seq]` ([[interpreter-step-31]]). Until this step the rounds' Mac rows run with `MO_CORES=1`. No syntax: placement stays the runtime's (chapter 10 §6).

## Orientation

`toolchain/src/turns.zig` (`place`, the fewest-live rule; `ask`, the parked fiber and `answers[seq]`; the cross-scheduler delivery and the eventfd wake; the runtime lock), `toolchain/runtime/mo_rt.c` (the native schedulers, the same rule and the same crossing), `toolchain/src/bench.zig` and `bench/results.tsv` (the rows: `echo-1k`, `kv-10k-get`, `http-1k`, jobq pairs and creates, the ledger, `100k asks`, `8 crunchers`, `200,000 short-lived processes`), `examples/programs/spread` (step 30's corpus program for placement), `../step30-mac/driver.log` and [[mac-scaling-run]] (the Mac's numbers per core count), step 31's deferred-reply bench (`processes/deferred-reply.mo` and the worker's driver under `bench/step31/` if kept), `mo-wiki/spec/design-v0/03-semantics.md` (Processes: "a process runs on one scheduler for its life"), `07-toolchain.md` (the bets). The Mac has 14 cores; `MO_CORES=N` sets the count; `MO_STATS=1` prints a line per scheduler.

## Write scope

`toolchain/`, `examples/programs/spread/` if the corpus program changes, and these spec lines only: the placement sentence in `03-semantics.md`'s Processes list, the bets in `07-toolchain.md`, the runtime line of `toolchain/README.md`, each with a "Session 8, step 34" line. Branch `main`, one commit per part, `Step 34 part X` in the subject, push after every commit, `zig build test` green at every commit.

## Parts

A. **Placement with the starter.** A process started from inside an update is placed on its starter's scheduler; the fewest-live rule stays for processes `main` starts and for a starter whose scheduler holds more than its share (say what the share is: live processes over schedulers, times a factor you choose and record). So an acceptor's worker runs where the acceptor runs, and the store a program starts from `main` stays where it is; a request path that never crosses costs what one scheduler costs. `MO_PLACE=spread` keeps step 30's rule for the comparison rows. Both runtimes; the same seed still gives the same trace under `mo test` (step 30's part C test), since placement is not part of the simulated order.

B. **The crossing made cheap.** Where a path must cross (a worker on one scheduler asking a store on another), the reply wakes the asker on its own scheduler without the round trip through the runtime lock that costs 3.4× today: read the path in `turns.zig` and `mo_rt.c`, find what it waits on, and take the waiting off the lock (a per-scheduler answer queue, or the eventfd carrying the answer's sequence). The parked fiber at 128 held asks under `mo run` (step 31's 0.46) is the same path from the other side: measure it before and after, and say what the fiber costs at rest.

C. **Measured on the Mac**, best of five, both runtimes, at 1, 4, and 14 cores, with `MO_PLACE=spread` beside the new rule at 14: `echo-1k`, `http-1k`, `kv-10k-get`, jobq pairs at 32 workers and creates (the change 4 program in `../mo-lang-erosion4-mo`, `MO_CORES` set the same way), the ledger, `100k asks` on one and two schedulers, `8 crunchers`, `200,000 short-lived processes`, the deferred reply at 8 and 128 askers. The `MO_CORES=1` rows unchanged within noise. Every scheduler's line from `MO_STATS=1` for the queue at 14 cores, so the placement is visible.

## Numbers

The table above. Done when at 14 cores no crossing row (`echo-1k`, `kv-10k-get`, the queue's pairs) is slower than at 1 core by more than 10 percent, and the CPU-bound rows (`8 crunchers`) still scale; where a row cannot meet that, the report says what it costs and why, with the scheduler lines beside it.

## Done when

`zig build test` green, the corpus green, `mo fmt` clean, the spec lines written, the numbers table with the `MO_STATS=1` lines, and a numbered list "Decisions the brief did not cover".

## Status at the pause (16 Sep 2026, 15:45 local)

Robert left with the Mac at 15:50. The worker (Opus, medium effort, briefed 15:08) finished part A and stopped on the lead's word: `1559554` "Step 34 part A" and `660b75c` "the bench programs formatted", both pushed, `zig build test` green at the first. Part A as committed: placement with the starter in both runtimes, `MO_PLACE=spread` keeping step 30's rule, a corpus program and a test for it. Parts B (the crossing made cheap) and C (the measurement at 1, 4, and 14 cores) are untouched and need the Mac's cores; a fresh worker resumes from part A's commit with the same brief. The worker's own note on what A did and what it measured is under `## The worker's note at the pause` below, as written to its pane.

## The worker's note at the pause

```
4. Why crossings are slow: 100k asks take 75 ms on one scheduler and about 4 s across two in
     the binary. A zero-timeout kevent costs 8 to 13 µs on this Mac, and the idle spin calls
     it every 64 turns, so pokes wait it out. Waking a sleeping thread costs 7 to 15 µs.
     Neither sweeps nor the runtime lock is the cause.
  5. Part B still needs:
     - Schedulers with no socket armed spin on the atomic poke alone, for a set time, then
       sleep on a futex; schedulers with sockets armed keep the poller path.
     - Held asks: constant-time removal from the parked list, and deadline scans only when one
       is due.
     - deferred.mo measured before and after at 8 and 128 askers, plus what a parked fiber
       costs at rest.
  6. Part C still needs:
     - The full table: best of five, both runtimes, 1, 4 and 14 cores, with spread beside the
       new rule at 14 cores.
     - Rows to add: the queue, the ledger, 8 crunchers (program not written yet), and spread
       with 200,000 processes.
     - The MO_STATS=1 lines for the queue at 14 cores.
     - The spec lines, the corpus and mo fmt checks, and the list of decisions the brief did
       not cover.
```

## Related

- [[interpreter-step-30]]
- [[mac-scaling-run]]
- [[interpreter-step-31]]
- [[10-language-after-the-rounds]]
- [[roadmap]]
