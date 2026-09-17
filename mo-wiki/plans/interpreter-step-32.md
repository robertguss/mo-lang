---
title: "Step 32: crash reports apart from the ring, and the reopening store"
created: 2026-09-16
updated: 2026-09-16
type: plan
tags: [runtime, agents, processes, tooling]
sources: [plans/erosion-round.md, plans/interpreter-step-23.md, spec/design-v0/03-semantics.md, spec/design-v0/10-language-after-the-rounds.md, decisions/decision-log.md]
status: done
---

# Step 32: crash reports apart from the ring, and the reopening store

Two small things P6 on Mo's change 2 program found ([[erosion-round]], "P6 on Mo's change 2 program"). One: under load the event ring turned over in the seconds between the queue's crash and the read, so `GET /crashes` was empty when it was needed most; a crash report is the one row an operator or an agent reads after the fact, and it must not compete with 10,000 `Updated` events a second for a place. Two: a restarted process runs its `state` initializers again with its capabilities, which is what chapter 3 calls the pattern for a store, and no corpus file shows it. No syntax.

## Orientation

`toolchain/src/events.zig` (the ring; `crashed` carries clause, message, state, seed), `toolchain/src/surface.zig` (`crashes` picks `.crashed` events out of the ring), `toolchain/src/surface.mo`, `runtime/mo_rt.c` (the native ring), `toolchain/README.md`'s runtime surface line, `mo-wiki/spec/design-v0/09-stdlib.md` `## Runtime`, `examples/processes/never-restart.mo` and `invariant-trips.mo` (the crash examples), `examples/processes/deferred-reply.mo` (a `# run:` file with a `main` and an `.expected`), `mo-wiki/plans/erosion-round-suite/reopen-run.mo` (the lead's probe: the file it reads says "one" before the crash and "two" after the restart, under both runtimes), `mo-wiki/plans/erosion-round-suite/p6-mo.py` (the probe that found the empty row; run it on the change 2 binary in `../mo-lang-erosion2-mo` built with `--surface`).

## Write scope

`toolchain/` and `examples/processes/`; these spec lines only: the `crashes` row of `09-stdlib.md` `## Runtime`, the runtime surface line of `toolchain/README.md`, and one line in `03-semantics.md`'s runtime surface section saying the crash reports are kept apart from the ring; each with a "Session 8, step 32" line. Branch `main`, one commit per part, `Step 32 part X` in the subject, push after every commit, `zig build test` green at every commit.

## Parts

A. **Crash reports kept apart from the ring**, both runtimes: the last 16 crash reports (`MO_CRASHES=N` for a binary, `mo run --crashes N`) in their own bounded store, written when the crash report is; `GET /crashes?n=` and `platform.runtime`'s `crashes` read that store, newest first; the `Crashed` event stays in the event ring as it is. A report's state snapshot is bounded as the crash report's printed one is (say what the bound is). A test in `zig build test` or the corpus: a process crashes under a stream of updates longer than the ring, and `crashes` still lists it.

B. **`examples/processes/restart-reopens.mo`**: a `# run:` corpus file with an `.expected`, after `deferred-reply.mo`'s shape: a process whose `state` opens a file from the `Fs` it was started with, crashed by an invariant, restarted `:always`, and asked what it read; the output shows the restart re-read the file. Its intent line says it is the pattern chapter 3 names for a store. If a `test` form can show the same (a `test rejects` ends at the trip today), add it; if not, say so in the report.

C. **The probe rerun**: `p6-mo.py` on the change 2 binary rebuilt with the new toolchain and `--surface`, default ring: the crash listed in `/crashes` with its clause, message, and snapshot; the numbers in the report.

## Numbers

Best of five, both runtimes: the standing bench rows (`kv-10k-get`, `http-1k`, jobq pairs a second) before and after, unchanged within noise; bytes resident for 16 kept crash reports with the bounded snapshot; the surface probe's row from part C.

## Done when

`zig build test` green, the corpus green including the new file, `mo fmt` clean, the three spec lines written, the numbers table, and a numbered list "Decisions the brief did not cover".

## Result

Written by one Opus session at medium effort, 09:01 to 10:04 on 16 Sep, three commits (`feec1f0`, `a3e5c15`, `d237108`), `zig build test` green at each. Accepted 10:20 after Fable's own runs.

**Part A.** Both runtimes keep the last 16 crash reports in a store of their own, apart from the ring: `mo run --crashes N`, `MO_CRASHES=N` for a binary, 0 keeps none; `crashes` reads it newest first (the spec row said oldest first before; changed). Each report's clause, message, and state snapshot is cut to 4,096 bytes at a character boundary with an "… N bytes more" ending; the printed report stays whole (3.4 MB on stderr for the P6 queue). The store is fixed slots, 3 × (4,096 + 40) bytes a report, reserved at the first crash (the first version allocated per text and cost 560 KiB for 16 reports). The `Crashed` event stays in the ring. A new corpus file, `examples/processes/crash-kept.mo`, driven by a new test in `corpus.zig`: under `mo run --events 64` and as a `--surface` binary with `MO_EVENTS=64`, a crash 200 updates back is still listed and none of the ring's last 64 events is a `Crashed`.

**Part B.** `examples/processes/restart-reopens.mo` with its `.expected`: a store whose state reads a file through the `Fs` it was started with, crashed by an invariant, restarted `:always`, prints "before the crash the store read one" and "after the crash and the restart the store read two". A `test` cannot show the re-read, since `test rejects` ends at the trip; the file has a test for the initializer reading through `Fs` and a `rejects` for the trip. An ask sent right behind the crashing message returns `Down` (the restart empties the mailbox), so the helper asks up to three times.

**Part C.** P6 rerun on the change 2 program built with the new toolchain and `--surface`, default ring, three runs a runtime: the crash listed every time with its clause, message, and snapshot; seven seconds after the crash the ring held no `Crashed` event and `/crashes` still listed it; nothing acknowledged lost. The probe's default `lease_ms: 5` message never trips anything (`lent` re-checks); the `Create` with `"bad queue"` is the kill.

**Numbers, best of five, before (`c80cd98`) and after.** `kv-10k-get` 121 → 123 µs under `mo run`, 98 → 99 as a binary; `http-1k` 64 → 69 and 65 → 66 µs (the `mo run` row from one bench run each, unrerun, flagged); `http-1k` resident 7,344 → 7,360 KiB and 2,752 → 2,768; jobq creates a second 4,077 → 4,044 and 5,331 → 5,366; jobq pairs at 32 workers 1,231 → 1,230 and 2,335 → 2,381; at 1 worker 899 → 788 under `mo run`, a row that swings 530 to 899 on either build. Sixteen kept reports with 64 KB states cost 224 KiB resident under `mo run` and 176 as a binary; the worst case at 16 reports is about 196 KiB.

**Verified by Fable.** `zig build test` green alone (196 of 196; one earlier run under the P6 probe's and the worker's bench load failed the `agent` program's corpus transcript, a run on wall-clock budgets, and passed on the rerun alone: a flake until it recurs). `restart-reopens.mo` matches its `.expected` under `mo run` and as a binary; `crash-kept.mo` passes; the P6 probe with the default ring lists the crash under both runtimes, nothing lost; a probe of three crashes of an `:always` child keeps 3 by default, 2 under `--crashes 2` and `MO_CRASHES=2`, 0 under 0, both runtimes.

**Carried, the worker's row 11.** Both runtimes still keep every full crash report for the whole run (the sim's crash list under `mo run`; the rendered strings never freed in a binary): 16 crashes with 64 KB states grew resident memory by about 2.3 MB with the store off. A service that crashes often grows without bound. A step of its own, queued. Also: `mo test` has no flag for the store's size (always 16); the memory row's `event_bytes` counts the ring, not the store.

## Related

- [[erosion-round]]
- [[interpreter-step-23]]
- [[interpreter-step-31]]
- [[10-language-after-the-rounds]]
- [[roadmap]]
