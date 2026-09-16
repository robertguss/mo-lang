---
title: "Step 32: crash reports apart from the ring, and the reopening store"
created: 2026-09-16
updated: 2026-09-16
type: plan
tags: [runtime, agents, processes, tooling]
sources: [plans/erosion-round.md, plans/interpreter-step-23.md, spec/design-v0/03-semantics.md, spec/design-v0/10-language-after-the-rounds.md, decisions/decision-log.md]
status: in-progress
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

## Related

- [[erosion-round]]
- [[interpreter-step-23]]
- [[interpreter-step-31]]
- [[10-language-after-the-rounds]]
- [[roadmap]]
