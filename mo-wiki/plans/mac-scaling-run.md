---
title: "The Mac scaling run: step 30 at 1, 4, 10, and 14 cores, the commands"
created: 2026-09-16
updated: 2026-09-16
type: plan
tags: [runtime, performance]
sources: [plans/interpreter-step-30.md, decisions/decision-log.md, plans/control-run-7-suite/measure.py]
status: in-progress
---

# The Mac scaling run

Robert's decision of 15 Sep 2026, 19:30: the suite and step 30's measurements on the M3 Max (14 cores, 10 performance and 4 efficiency, 96 GB) at `MO_CORES` 1, 4, 10, and 14, in parallel with the rounds. The question is scaling on all fourteen cores against one on the same machine, and where the curve stops; it is not a comparison with the VM. The commands are one script; the table goes beside step 30's in [[interpreter-step-30]]'s Result.

## Before

The Mac has not run the suite since 14 Sep morning, and neither step 29b's `MAP_NORESERVE` reservation nor step 30's threads have run there. So the suite comes first, and a failure there is the first result.

## The commands

From the repo root on the Mac, on `main` after 16 Sep, with Zig 0.16 on PATH:

```
git pull
mo-wiki/plans/interpreter-step-30-suite/mac-run.sh
```

It builds, runs `zig build test` (silent on success, minutes cold), builds the queue and the ledger as native binaries, then per core count: `mo-bench` best of five, the queue's 100k creates and lease-and-ack pairs at 1 and 32 workers five times (`control-run-7-suite/measure.py`, the same client as the rounds), and the ledger's 100k transfers from 32 clients five times (`ledger_load.py`, step 30's driver with its memory read made to work on a Mac). Results land in `../step30-mac/`, one text file per run and `driver.log` with one line per result; `driver.log` is what to paste back. Fewer core counts: `mac-run.sh 1 14`. About an hour and a half in all.

## What to read

| row | the VM, 1 core / 4 cores | what the Mac answers |
|---|---|---|
| queue pairs a second, 32 workers | 342 / 423 (fsync-bound) | whether the Mac's disk moves it, and whether cores do |
| ledger transfers a second | 1,990 / 1,897 | whether 10 and 14 lift it or the fsync pool is the ceiling |
| bench `http-1k`, `kv-10k-get`, `replay-1m` | in step 30's table | the curve from 1 to 14, and the efficiency cores' share |

## Related
- [[interpreter-step-30]]
- [[control-run-8]]
- [[roadmap]]
