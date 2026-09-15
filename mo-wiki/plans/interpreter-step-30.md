---
title: "Step 30: processes on every core, brief for the worker"
created: 2026-09-15
updated: 2026-09-15
type: plan
tags: [runtime, processes, performance]
sources: [plans/interpreter-step-21.md, plans/interpreter-step-29.md, plans/interpreter-step-29b.md, spec/design-v0/03-semantics.md, spec/design-v0/07-toolchain.md, plans/control-run-7.md]
status: in-progress
---

# Step 30: processes on every core

Since step 21 every process is a fiber on main's thread, so a Mo program uses one core of four while Go's job queue in round 7 used all of them. Processes share nothing and speak only by message, which is the property that makes running them on several threads safe. This step is the runtime's; the language does not change, no corpus program's source changes. Sketched 15 Sep at 01:57; the brief written at 12:45 after steps 29 and 29b landed. Robert's call (15 Sep, midday): this runs before round 8, so round 8's speed and memory columns compare Mo on every core.

## Orientation

`toolchain/src/turns.zig` (the scheduler: its header says the model, one thread, updates handed out round by round in start order, a delivery borrowing a fiber from a pool, the sweep that ends processes nothing reaches, `kept_fibers`, `reserve_process` and the `spilled` count from step 29b); `fiber.zig` (the switch, the guarded stacks); `poller.zig` (kqueue or epoll on main's thread, a waiter armed once and reported once, `nobody`); `vm.zig` (`call_depth` and `call_high` are `threadlocal` already because the runner runs tests on threads; the per-process `Vm`; the message packing counts); `region.zig` (step 29b's 64 GiB `MAP_NORESERVE` reservation per process and the walk that compacts the frames waiting in whole-statement calls; the walk runs over one process's frames only, which is what makes a scheduler per core possible without a lock); `sim.zig` (`Mo.Sim`, one thread and one fixed order, the seeded run's choices, `--faults`); `server.zig` (`Mo.Server`, the store's `fsync` at line 370, "on disk before `Ok`"); `net.zig`, `http.zig` (where a call gives up the thread); `events.zig` and `surface.zig` (the event ring and the `processes` rows the surface serves); `runtime/mo_rt.c` (the same design in C: `mo_spawn` and `mo_start_supervisor` near 5018, `mo_send` at 5100, `mo_send_later` at 5451, the fiber swap at 5852, the poller at 5958, the `fsync` at 3691; `pthread.h` is included and unused). What steps 29 and 29b changed and this step must keep: `restart: :never` and the `Dropped` event, `platform.exit` dropping every pending delayed send when `main` returns, the delayed-send heap and simulated time moving only in a wait, generational compaction in `reduce` and `fold_lines`, the walk through waiting frames, the address-space reservation. The spec sentences that hold: `03-semantics.md` line 24 (direct style, green threads, no coloring), the Processes list (an update is a transaction; a message is a deep copy; a process ends when nothing reaches it), the runtime surface section (a `Runtime` read is a snapshot between two updates), and chapter 7's bets. The round 7 numbers to beat (`plans/control-run-7.md`, "On Robert's measure"): Go 478 lease-and-ack pairs a second at 32 workers to Mo's 981 on one core; the ledger's 1,370 transfers a second at 32 clients after step 29b.

## Write scope

`toolchain/`, and the spec lines in `03-semantics.md` (the Processes list) and `07-toolchain.md` that the rule in part A adds; `examples/` only for a new corpus file under `processes/` or `programs/` that shows the rule, never a change to a program's source. Branch `session-05`, one commit per part, `Step 30 part X` in the subject, push after every commit, `zig build test` green at every commit. Long runs detached (`setsid nohup`) with a timeout and a memory watchdog at 9 GB: the harness's low-memory stop kills a background job while the machine has memory free. Zig 0.16 is at `~/.local/share/mise/installs/zig/0.16.0/bin`.

## Part A: the rule, and the schedulers

The rule, stated in the report in one sentence and added to the Processes list: **a Mo program runs its processes on every core; a process runs on one scheduler for its life; an update is still one transaction on one thread, and what a process sees is unchanged, since nothing is shared and a message is a copy.** Then:

1. A scheduler per core, each running fibers exactly as `turns.zig` does today: its own ready queue, its own fiber pool, its own poller or a share of one (the worker chooses and says why in the report; a poller per scheduler avoids a cross-thread wake on every socket, one poller is simpler; measure `http-1k` both ways if the choice is not obvious from the first numbers). The count comes from `MO_CORES` when set and from the machine otherwise, in both runtimes; `MO_CORES=1` is today's runtime exactly. `main` runs on scheduler 0 and hands the thread out as it does now.
2. A process is placed at `start` on the scheduler with the fewest live processes (the count, not a load estimate; say if the ledger's numbers argue for another rule) and stays there for its life; no migration. A supervisor's children may land on different schedulers; the supervisor's restart policy, `max_restarts`, and the `:never` rule are unchanged, and the report of a crash is the same text.
3. A `send` or `ask` to a process on another scheduler pushes the packed message onto that process's mailbox under that mailbox's lock (a mutex per mailbox, or an MPSC queue per scheduler; the worker chooses, says why, and measures the cost on `echo-1k`) and wakes the target's scheduler if it is idle in its poller (an eventfd or a pipe). A reply crosses back the same way. The mailbox bound, backpressure, `Idle`, deadlines, the delayed-send heap (one per scheduler, or one shared with a lock; say which), `Timeout`, and `Down` behave as they do now. A `send` to a process on the same scheduler takes the path it takes today.
4. The sweep (step 19) and the region walk (step 29b) run on the process's own scheduler over that scheduler's processes only. Whether a process has ended (nothing reaches its handle) needs handles held on other schedulers counted: say how (a stop-the-world count at a quiet moment, or reference counts on handles crossing schedulers), and test it with 200,000 short-lived processes started from several schedulers.
5. `platform.exit` stops every scheduler and keeps the code; a crash report from any scheduler prints whole, never interleaved with another's.

## Part B: `fsync` off the scheduler

A process that writes through the store waits on `fsync` (`server.zig` 370 and `mo_rt.c` 3691), and today that stalls every process on the thread. The call gives up the scheduler as a `Net` call does: the write and the sync run on a small pool of blocking I/O threads (or `io_uring` on Linux if the worker judges it worth it, said why), the fiber parks, and the scheduler runs other processes; `Ok` is returned only once the data is on disk, so the store's "on disk before `Ok`" sentence and the failure model (a kill under load loses no acknowledged write) hold. Both runtimes. Measured: the ledger's transfers a second at 32 clients and the queue's pairs a second, 1 and 4 cores, with the fsync on and off the scheduler.

## Part C: the simulator, the surface, and the corpus

1. `mo test`, `--sim`, and a test binary run on one thread with the fixed order and the seeded choices unchanged: the same seed gives the same trace as before this step, shown by a test that records a seeded trace of `programs/ledger/journal.mo` and of `processes/registry.mo` before and after (a checked-in trace or a comparison against the step 29b binary; say which).
2. The runtime surface's `processes` rows gain a scheduler field, `events` records a process's placement at its start, `MemoryInfo` still sums every process's regions; `MO_STATS=1` prints per scheduler.
3. The corpus green under `mo test`, `mo run`, and as binaries; every `.expected` unchanged; the corpus files whose output depends on the order two processes print in, if any, listed in the report with what was done (nothing in the corpus should depend on it, since the spec never promised an order between two processes; if one does, say so and leave the file as it is, with a row for Fable).
4. `mo fmt --check` clean; the `verified:` lines untouched (a hand-written one is refused by MO0317).

## Part D: measured

Best of five, native and interpreted, at `MO_CORES=1` and `MO_CORES=4`, with the step 29b `mo` as the baseline for the 1-core rows:

1. The job queue, `examples/programs/jobq`, under `mo-wiki/plans/control-run-7-suite/measure.py` (`--serve '<cmd> serve {dir} --port {port}'`, 100k creates, then pairs a second at 1 and 32 workers, resident memory after): creates a second, pairs a second at 1 and 32, memory at 100k, and a restart on the log to `/health`.
2. The ledger, `examples/programs/ledger`, at 32 clients under `../mo-lang-replay-1m/replay.py` (200 accounts, 32 clients, a fresh key each; never touch that folder's data or `replay-1m-only.txt`; write into a scratch folder): transfers a second, memory after 100k entries, and the evidence log's 1M replay time and peak (`replay-only.py <dir> <port> <cap-MiB>`), which is one process and should not change.
3. The bench rows `echo-1k`, `http-1k`, `kv-10k-get`, `logstat-4k`, `replay-1m`; a process at rest (`processes/registry.mo`'s 10,001 handles); 65,530 idle connections still held; 200,000 short-lived processes from several schedulers freed (the step 19 reproduction) and their memory flat.
4. A kill under load at 4 cores: 32 clients writing to the ledger, `SIGKILL` at a random moment, replay, balances equal to the postings, five times.
5. The cost of the cross-scheduler path: a two-process ping-pong of 100k asks with both on one scheduler and on two.

## Numbers

The tables above, before and after, and a sentence on each row that moved more than 10 percent. The queue's pairs a second at 32 workers on 4 cores against Go's 478 is the row round 8 reads.

## Done when

The rule stated and in `03-semantics.md`; `MO_CORES=1` gives today's runtime and `MO_CORES=4` runs processes on four threads in both runtimes; a seeded test's trace unchanged; the store's `Ok` still means on disk and the kill under load loses nothing, five times; the corpus green and no `.expected` changed; the numbers; pushed; a numbered list "Decisions the brief did not cover".

## Related
- [[interpreter-step-29b]]
- [[interpreter-step-29]]
- [[interpreter-step-21]]
- [[control-run-7]]
- [[decision-log]]
