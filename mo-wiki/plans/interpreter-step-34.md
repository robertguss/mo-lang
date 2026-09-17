---
title: "Step 34: placement, so the Mac's cores stop costing"
created: 2026-09-16
updated: 2026-09-16
type: plan
tags: [runtime, performance, processes]
sources: [plans/interpreter-step-30.md, plans/mac-scaling-run.md, plans/interpreter-step-31.md, spec/design-v0/03-semantics.md, spec/design-v0/07-toolchain.md]
status: done, accepted 16 Sep 2026, 21:20 local (four rows past the 10 percent criterion by the main-starts rule, recorded)
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

## Result (16 Sep 2026, 21:20 local; parts B and C by a second Opus session, 16:50 to 20:46)

Commits `1559554` and `660b75c` (part A, the afternoon), `9716cd8` (part B), `d429dd9` (part C), all on `main`; `zig build test` green at each and in Fable's run after the merge (exit 0, two minutes warm). The full tables are in `toolchain/bench/step34/RESULTS.md`; the worker's report is quoted in the decision log's rows.

**Part B, the crossing made cheap.** 100,000 asks across two schedulers took 4.0 to 5.6 s on the Mac (part A's build, one run) and take 0.14 s as a binary and 0.15 s under `mo run` now, against 0.07 to 0.08 s on one scheduler, at 2, 4, and 14 cores alike. The cost was never the runtime lock or the sweeps: a poked scheduler ran a zero-timeout `kevent` on every poke (8 to 13 µs on this Mac), and with the poke flag and the sleep state apart the Zig runtime lost a wake now and then and a scheduler slept out its full second. Now a scheduler spins 200 µs on its poke, looks at its poller only when a socket of its own is armed, and otherwise sleeps on its state word (a futex; a condition variable in a binary); the poke and the sleep are one atomic word; a sweep's end wakes only the schedulers it held back; a parked process leaves the parked list in constant time and deadlines are scanned only when one is due; the lock spins 20,000 times before it waits. A parked fiber at rest costs about 24 KiB under `mo run` and 7.5 KiB in a binary; at 128 held asks on one core the deferred reply runs at 0.59 of the send shape (step 31 measured 0.46).

**Part C, a regression found and fixed.** With placement beside the starter, a process that starts processes and asks them never parks, so sweeps missed and ended processes piled up: 200,000 short-lived processes under `mo run` kept 2,605 ids and 2 GB at 2 cores and passed 4 GB at 4 on part A's build, where step 33 kept 47 to 164 ids. An update about to deliver an ask on its own scheduler now steps aside while a sweep waits or is due (both runtimes): 81 to 127 ids, 72 to 108 MiB, and the row faster than step 33's at 14 cores (3.1 s against 5.8 under `mo run`, 5.0 against 6.7 as a binary). No unit test covers the step-aside (the worker's decision 12): carried.

**The table** (best of five unless marked, ms unless marked, `run` / `bin`; the change 4 queue from `../mo-lang-erosion4-mo`; part A's 14-core column from the pause):

| row | 1 core | 4 cores | 14 cores | 14, spread | part A, 14 |
|---|---|---|---|---|---|
| `echo-1k` | 24.4 / 27.2 | 33.6 / 36.3 | 35.0 / 37.9 | 29.6 / 35.4 | 83.6 / 84.9 |
| `kv-10k-get` | 428 / 212 | 434 / 256 | 441 / 257 | 444 / 258 | 1,249 / 1,043 |
| `http-1k` | 57.6 / 55.1 | 60.2 / 58.6 | 63.3 / 59.2 | 63.6 / 60.4 | 70.2 / 67.1 |
| queue creates a second, bin (best of 3) | 8,367 | 7,254 | 6,278 | 6,066 | 5,349 |
| queue pairs a second at 32 workers, bin (best of 3) | 456 | 453 | 444 | 445 | 451 |
| queue creates / pairs at 32, run | 5,715 / 195 | 5,437 / 203 | 5,276 / 206 | 5,232 / 206 | |
| ledger transfers a second, bin (best of 3) / run | 4,819 / 659 | 4,814 / 651 | 4,347 / 646 | 4,321 / 640 | |
| 100k asks, one scheduler, s, run / bin | 0.080 / 0.072 | 0.083 / 0.074 | 0.082 / 0.074 | 0.149 / 0.138 | |
| 100k asks, two schedulers, s, run / bin | 0.080 / 0.072 | 0.153 / 0.139 | 0.151 / 0.140 | 0.152 / 0.140 | 4.0 / 4.7 (part B's baseline) |
| 8 crunchers, run (2M rounds) / bin (20M) | 1,307 / 511 | 344 / 141 | 179 / 85 | 181 / 85 | |
| 200k short-lived processes, s, run / bin | 8.65 / 8.39 | 1.79 / 1.92 | 3.13 / 4.95 | 3.37 / 6.29 | bin 5.46 |
| deferred reply, 8 askers, reply / send, run | 29 / 30 | 31 / 46 | 41 / 61 | 42 / 61 | 90 / 135 |
| deferred reply, 128 askers, reply / send, run | 64 / 38 | 43 / 32 | 62 / 65 | 62 / 65 | 61 / 54 |
| deferred reply, 128 askers, reply / send, bin | 20 / 19 | 21 / 30 | 46 / 71 | 47 / 69 | |

The 1-core rows match part A within noise except `kv-10k-get` under `mo run` (428 against 396). **Against the criterion at 14 cores against 1:** met by `kv-10k-get` under `mo run` (+3 percent), the queue's pairs (−3 percent), and the crunchers (7.3× under `mo run`, 6.0× as a binary); **not met** by `echo-1k` (+43 percent `mo run`, +39 binary: `main` starts both the client and the acceptor, so they land on different schedulers by the rule, and each round trip wakes two kqueue threads over the socket, about 10 µs a trip), the binary's `kv-10k-get` (+21: `main` starts the store, journal, gate, and listener on schedulers 0 to 3, the listener's worker lands with it, and all 10,001 asks cross to the store), and the queue's creates (−25, not a row the criterion names: every create asks the queue `main` started on scheduler 1). The `MO_STATS=1` lines for the queue at 14 cores (binary): the acceptor's scheduler 2 placed 17,518, 17,517 with their starter; every other scheduler placed 5,800 to 10,600 by the fewest-live rule, each with as many asks across as it placed; under `MO_PLACE=spread` `with_starter` is 0 everywhere (the lines in `RESULTS.md`). What remains is placement for what `main` starts, which the brief left as it was (the worker's decision 10): a floor on the starter's share would keep more workers with their acceptor, and the queue's workers would still cross to the queue.

**Fable's probes** (pane `w44:p9` and `w44:pA`, after the suite). The ledger under `mo run` at 1 core on step 33's binary: 669 transfers a second in 149.5 s, peak 593 MiB, each tenth of the load slower than the last (9 s to 20 s), the same as this step's 650 to 659: the interpreter ledger's cost is step 33's carried compaction copy (about 39 percent of samples in `vm.Vm.compact`, most in `copySlice`'s forwarding lookup), not this step's. The queue's pairs a second at 32 workers, 1 core, binary, each generation's program built with this step's `mo`: round 7's 4,040 and 4,052, change 1's 4,045 and 4,035, change 2's 4,142 and 4,121, change 3's 4,068 and 4,041, **change 4's 452 and 457** (1 worker: 2,000 for every earlier generation, 730 for change 4), and change 4 on step 33's binary 455 and 458. The 456 in the table is the change 4 Mo program's, nine times slower on the lease path than the program it was handed, on either binary: a performance erosion in generation four that the fifth suite did not count, recorded on [[erosion-round]] with the three baselines' change 4 rows.

**The orphan.** The first ledger phase was contaminated by the worker's wrapper: the ledger load script killed the watchdog, which orphaned the `mo run` server; every later run failed to bind the port and talked to the orphan, which Fable found at 18:57 at 99 percent CPU and 1.3 GB, thirty-one minutes old, compacting a book the later runs kept growing. Killed; the phase rerun with `ledger_probe.py`, which starts the server in its own process group, kills it TERM then KILL, and checks nothing is left (every run: none).

**Carried.** The crunchers binary's memory (about 15 bytes a loop iteration a running process, freed only when the update ends: 161 MiB at 1 core and 1,223 at 8 or more for 10M rounds, identical on step 33's `mo`; past 6 GB at 100M rounds at 4 cores, so the binary rows use 20M); the interpreter ledger's compaction cost; the 780 KB a process at rest; a unit test for the step-aside; placement for what `main` starts.

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
