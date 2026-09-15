---
title: "Step 29b: replay memory on a real log, brief for the worker"
created: 2026-09-15
updated: 2026-09-15
type: plan
tags: [runtime, performance, processes]
sources: [plans/interpreter-step-29.md, plans/program-6.md, decisions/decision-log.md]
status: in-progress
---

# Step 29b: replay memory on a real log

Step 29's part C made `reduce` and `fold_lines` compact in generations, and the ledger's 1M replay on the worker's generated log went from 716 s to 81 s at a 2.5 GB peak. Fable's acceptance probe replayed a different 1M log, one a real HTTP session wrote, and the replay passed 8 GB fifteen seconds after the fold ended. The brief's "bounded memory" is not met on a real log. This step finds where the memory is made and makes the rule hold: memory during an update is bounded by what the update still reaches, in every loop shape, not two.

## Orientation

[[interpreter-step-29]] and its Result; the evidence folder `/home/exedev/Projects/mo-lang-replay-1m/` (never deleted): `data-1000000/ledger.log`, 701 MB, one million transfers written over HTTP by `replay.py` (200 accounts with a large overdraft, 32 clients, a fresh idempotency key each, no holds); `replay-only.py <dir> <port> <cap-MiB>`, the instrument (starts `serve`, polls `/health`, samples resident memory every 20 ms, prints the peak and a curve); `replay-1m-only.txt`, the curve that step 29 left: 532 MiB at 15 s, 1,005 at 60, 1,111 at 75, 8,163 at 90, killed past 9,000 at 101 s. The live server that wrote that log sat at 1,586 MiB with the whole book in memory, so the book fits in 1.6 GB and the replay makes about 7 GB more in fifteen seconds. `examples/programs/ledger/records.mo` (`opened_book`: the fold in `replayed`, then `rebuilt(own.loading)`, the phase after the fold), `index.mo` (the book's maps; `pushed` caps a list at 100), `store.mo` (the table), `journal.mo` lines 55–70 (what runs after `opened_book`). `toolchain/src/vm.zig`, `runtime/mo_rt.c`: step 29's generational compaction in `reduce` and `fold_lines`, and what a `for`, a `while`, a recursion, or a chain of calls does with what it no longer reaches during one update.

## Write scope

`toolchain/`, `examples/`, and the spec lines in `03-semantics.md` a runtime rule changes. The ledger's program is changed only if the report says the growth is the program's, and then a diagnostic or stdlib row that would have shown it comes with the change. Branch `session-05`, one commit per part, `Step 29b part X` in the subject, push after every commit, `zig build test` green at every commit. Long runs detached (`setsid nohup`) with a memory watchdog at 9 GB: the harness's low-memory stop kills a background job while the machine has memory free.

## Part A: where the memory is made

Replay the evidence log native with the instrument and a profile: which phase (the fold, `rebuilt`, `expiries` and `scheduled`, the first flush), which loop shape, which values are made and not freed. A table of phases with time and memory. Say whether the same phase grows on the worker's generated log (1,001 accounts) and why it did not show there.

## Part B: the rule holds

Whatever the phase, the runtime frees what an update no longer reaches while the update runs, in every loop shape (`for`, `while`, recursion, a chain of calls, `reduce`, `fold_lines`), with the generational scheme of part C or a better one, in both runtimes. If the growth turns out to be a value the program keeps that the book does not need, say so, fix the program's shape, and add what would have shown it (a runtime event, a surface row, or a diagnostic).

## Part C: measured

The evidence log at 1M native, time and peak, before and after, best of three; the phases' table after; the worker's generated log at 100k, 500k, 1M native again; the 100k replay under `mo run`; `kv-10k-get`, `http-1k`, `logstat-4k` within noise; the ledger's transfers a second at 32 clients within noise; the whole suite green, `mo fmt --check` clean.

## Done when

The evidence log's 1M replay finishes native with a peak under twice its live book (under 3,200 MiB), the phase table says where the memory went, the rule is stated in the report in one sentence and, if it changed, in `03-semantics.md`; green at every commit; the numbers; pushed; a numbered list "Decisions the brief did not cover".

## Related
- [[interpreter-step-29]]
- [[interpreter-step-30]]
- [[program-6]]
- [[decision-log]]
