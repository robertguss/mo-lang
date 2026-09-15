---
title: "Step 29b: replay memory on a real log, brief for the worker"
created: 2026-09-15
updated: 2026-09-15
type: plan
tags: [runtime, performance, processes]
sources: [plans/interpreter-step-29.md, plans/program-6.md, decisions/decision-log.md]
status: done
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

## Result

Accepted 15 Sep 2026, 12:20 UTC. Three commits (A, B, C), green at each, the suite green at the end, `mo fmt --check` clean; about 4 h 40 min of worker time, most of it three measurement rounds as fixes landed. Part A found the cause: a process region reserved 1 GiB of address space and moved into a larger one only between updates; the journal's `Open` is one update, and `rebuilt`'s last `reduce` filled the region at 77 s, after which every allocation came from malloc, which no compaction frees and which left the region's top where it was, so no safe point compacted again: about 650 MiB a second. The step-29 worker's generated log peaked 55 MiB short of the reservation. `MO_STATS=1` now ends with `spilled`. Part B: a process region reserves 64 GiB of address space (`MAP_NORESERVE`) while live regions total under 16 TiB, and 1 GiB after; and the walk: a call made as a whole statement is a safe point where the frames waiting in such calls are compacted together, so a recursion frees each level's garbage. Part C: measuring found the walk 13% slower and fixed it (a trigger on growth past twice the known live, roots copied at the call, one lookup instead of two, view copies no longer per view); the numbers. The ledger's program is unchanged: the growth was the runtime's.

Numbers (the worker's, native unless marked, best of three, bench best of five): the evidence log's 1M replay killed past 9,000 MiB at 88 / 85 / 85 s → 94.8 s at 2,323 MiB; generated 100k 7.76 → 7.98 s at 203 MiB; generated 500k 35.6 → 35.8 s at 1,087 MiB; generated 1M 81.2 → 80.3 s, 2,490 → 2,153 MiB; the 100k replay under `mo run` 168.1 → 144.8 s, 482 → 510 MiB; kv-10k-get 302.6 → 261.6 ms and 155.6 → 144.0 native; http-1k 37.8 → 36.6 and 33.2 → 34.0; logstat-4k 100.9 → 97.6 and 20.4 → 24.0 (an outlier; reruns 21.2, 21.7, 20.1); transfers a second at 32 clients 1,335 → 1,370; for, reduce, map, a chain of calls, fold_lines 0–9 MiB over 300,000 steps; a recursion 9,000 deep 89 → 4 MiB native, 589 → 47 under `mo run`.

Fable's probes: the evidence log replayed native twice with a fresh binary, 97.2 and 95.1 s at a 2,323 MiB peak settling at 1,057 MiB; Fable's 100k HTTP-written log under `mo run` in 49.0 s at 471 MiB; the suite green. The phase table says the final peak is the book held twice while it is compacted, not a leak. Left: the peak is twice the book at the last compaction; a ledger that pages its history is still a program-shape question, for Robert.

## Related
- [[interpreter-step-29]]
- [[interpreter-step-30]]
- [[program-6]]
- [[decision-log]]
