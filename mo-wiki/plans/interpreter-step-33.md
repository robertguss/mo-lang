---
title: "Step 33: the crash report freed, and the interpreter's abort on a full disk"
created: 2026-09-16
updated: 2026-09-16
type: plan
tags: [runtime, processes, performance, tooling]
sources: [plans/erosion-round.md, plans/interpreter-step-32.md, spec/design-v0/03-semantics.md, decisions/decision-log.md]
status: in-progress
---

# Step 33: the crash report freed, and the interpreter's abort on a full disk

Two things generation three of the erosion round found on the change 3 program ([[erosion-round]], "Generation three, the result"). One: both runtimes keep every crash report's rendered text for the whole run, so a store that restarts itself after a failure leaks its own size on every restart; the Mo maintainer measured about 44 MB a restart on a 20,000-job queue and 1.4 GB resident after 30 (`erosion-round-suite/results/e3-mo-TOOLCHAIN-BUGS.md.txt`, §5, with the reproduction). Step 32 recorded it as carried; change 3 makes it a leak per failure. Two: under `mo run` alone, the third suite's unwritable category ended with the interpreter exiting on signal 6 (an abort) when the service was stopped and started on the RAM-disk folder after the disk had been filled and freed; the binary passed the category whole. No syntax.

## Orientation

`toolchain/runtime/mo_rt.c` (`report_text`, `raise_report`, `last_report`, the rendering of a crashed process's state, its state before, and the message log; the invariant's clause renders the state a third time), `toolchain/src/sim.zig` (`crashes`, the list of `contracts.Report` appended at every crash and read by the runner and the surface; `kept_crashes` from step 32), `toolchain/src/contracts.zig` (`Report`), `toolchain/src/events.zig` (step 32's crash store with its 4,096-byte cut), `toolchain/src/store.zig` or wherever `Fs.append` and the log's open and rewrite live, `mo-wiki/plans/erosion-round-suite/defects2.py` (`t_unwritable`: a 64 MB RAM disk filled under load, freed, then the service stopped and started on the folder), the change 3 Mo program in `../mo-lang-erosion3-mo/examples/programs/jobq` (its toolchain binary is that worktree's; build with this repo's `mo` to reproduce), `mo-wiki/spec/design-v0/03-semantics.md` (the failure model: what a crash report holds).

## Write scope

`toolchain/` only, and one line each in `03-semantics.md`'s failure model (what the runtime keeps of a report after printing it) and `toolchain/README.md`, each with a "Session 8, step 33" line. Branch `main`, one commit per part, `Step 33 part X` in the subject, push after every commit, `zig build test` green at every commit.

## Parts

A. **The report freed**, both runtimes. After a crash report is printed to stderr and its cut copy is in step 32's store, nothing of it stays resident: the sim's `crashes` list keeps what the runner and the surface still read (the clause, the process, whether it restarted, a bounded snapshot) and not the rendered state; the C runtime frees the rendered strings once the report is written. What the runner prints at the end of a failed seed (the last events, the report) must still print. Measure with the maintainer's reproduction: a 20,000-job log, `jobq serve --crash-every 1 --max-restarts 1000`, 30 creates with a `/health` between each; resident memory before and after, both runtimes; the target is growth under 1 MB a restart. Also the state rendered once, not three times, if the invariant's clause can reuse the report's.

B. **The abort under `mo run` on the freed disk.** Reproduce with `defects2.py --only unwritable` on the change 3 program under `mo run` (the suite makes the RAM disk itself; `--log-format mo`), read the signal 6's cause (a Zig panic or `unreachable` on the reopen: a torn line, a short read, an `ENOSPC` left in the log's tail, the RAM disk's page size), fix it so the interpreter does what the binary does, and add the case to `zig build test` or the corpus with a fixture that reproduces it without the RAM disk if one can.

C. **The rerun**: `defects2.py --only unwritable` green under `mo run` and as a binary on the change 3 program; `defects3.py --only restart` and `--only budget` on the same, both runtimes; the P6 probe (`p6-mo.py`, the `Create` with `"bad queue"`) with the resident memory read from `/memory` after the restart.

## Numbers

Best of five, both runtimes: the standing bench rows unchanged within noise; resident memory per restart before and after part A on the 20,000-job queue; the time of one restart on that log (the maintainer reported 0.15 s) and on a 100,000-job log (1.38 s reported, over the spec's one second: record it, the fix is not this step's unless it is the report's rendering).

## Done when

`zig build test` green, the corpus green, `mo fmt` clean, the two spec lines written, the numbers table, part C's runs, and a numbered list "Decisions the brief did not cover".

## Related

- [[erosion-round]]
- [[interpreter-step-32]]
- [[01d-job-queue-change-3]]
- [[roadmap]]
