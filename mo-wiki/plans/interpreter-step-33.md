---
title: "Step 33: the crash report freed, and the interpreter's abort on a large log"
created: 2026-09-16
updated: 2026-09-17
type: plan
tags: [runtime, processes, performance, tooling]
sources: [plans/erosion-round.md, plans/interpreter-step-32.md, spec/design-v0/03-semantics.md, decisions/decision-log.md]
status: done
---

# Step 33: the crash report freed, and the interpreter's abort on a large log (titled "a full disk" until the Result found the cause)

Two things generation three of the erosion round found on the change 3 program ([[erosion-round]], "Generation three, the result"). One: both runtimes keep every crash report's rendered text for the whole run, so a store that restarts itself after a failure leaks its own size on every restart; the Mo maintainer measured about 44 MB a restart on a 20,000-job queue and 1.4 GB resident after 30 (`erosion-round-suite/results/e3-mo-TOOLCHAIN-BUGS.md.txt`, §5, with the reproduction). Step 32 recorded it as carried; change 3 makes it a leak per failure. Two: under `mo run` alone, the third suite's unwritable category ended with the interpreter exiting on signal 6 (an abort) when the service was stopped and started on the RAM-disk folder after the disk had been filled and freed; the binary passed the category whole. No syntax.

## Orientation

`toolchain/runtime/mo_rt.c` (`report_text`, `raise_report`, `last_report`, the rendering of a crashed process's state, its state before, and the message log; the invariant's clause renders the state a third time), `toolchain/src/sim.zig` (`crashes`, the list of `contracts.Report` appended at every crash and read by the runner and the surface; `kept_crashes` from step 32), `toolchain/src/contracts.zig` (`Report`), `toolchain/src/events.zig` (step 32's crash store with its 4,096-byte cut), `toolchain/src/server.zig` or wherever `Fs.append` and the log's open and rewrite live, `mo-wiki/plans/erosion-round-suite/defects2.py` (`t_unwritable`: a 64 MB RAM disk filled under load, freed, then the service stopped and started on the folder), the change 3 Mo program in `../mo-lang-erosion3-mo/examples/programs/jobq` (its toolchain binary is that worktree's; build with this repo's `mo` to reproduce), `mo-wiki/spec/design-v0/03-semantics.md` (the failure model: what a crash report holds).

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

## Result

Written by one Opus session at medium effort, 11:21 to 12:47 on 16 Sep, three commits (`42323b3` B, `a7d42a4` A, `df89edf` C), `zig build test` green at A's code (198 of 198). Accepted 13:05 after Fable's own runs.

**Part B first, because A's measurement needed it.** The abort had nothing to do with the RAM disk: `mo run` panicked opening any jobq log of about 8,000 jobs. Compaction copies a string once for every value that points at it, so the copy can come out larger than what was there; the region's top then passed its recorded high-water mark and `high - top` went below zero, a Zig panic (signal 6). The C runtime had the same subtraction, and its unsigned wrap-around only released some pages, which is why the binary passed. Both raise the mark first now; a unit test in `vm.zig` reproduces the panic without a disk. The copy-per-reference itself (about half again on jobq's log) is left as a finding.

**Part A.** A crash report is written to stderr and then freed in both runtimes; only its cut copy in step 32's store stays, and a `Crashed` event in the ring holds the report's number in that store, not its text. The interpreter renders reports into a per-vm arena emptied after each crash. The C runtime needed its own memory: `free()` left the blocks resident on macOS (360 MiB after ten restarts), so reports are rendered into chunks the runtime maps and unmaps itself. A corpus test restarts a multi-MiB process twenty times under both runtimes and reads resident memory from inside the program; the old code fails it (71 and 113 MiB), the new passes.

**Numbers, best of five, both runtimes (the worker's, `toolchain/bench/step33/`).** Growth per restart on a 20,000-job queue over 30 restarts: 46.1 to 0.27 MiB as a binary, 27.95 to 0.00 under `mo run`; resident after the 30: 1,412 to 37 MiB and 902 to 64. On 100,000 jobs the first restart still adds 10.3 and 4.6 MiB, the queue's region settling, flat from the ninth. One restart: 0.266 s at 20,000 jobs as a binary (0.905 under `mo run`), 1.45 s at 100,000 (4.91): the spec's one second is unmet at 100,000 and this step did not touch it, since it is the replay plus the report. P6's `/memory` after four kills: 111.5 to 45.5 MiB as a binary. The standing bench unchanged within noise; `kv-50k-set-rss-kib` is about 340 MiB on this Mac against about 40 in `results.tsv`, the same before and after, a baseline gap to explain.

**Verified by Fable (12:54 to 13:02).** `zig build test` green alone. The maintainer's reproduction on the change 3 program rebuilt with the new toolchain, 20,000 jobs and 30 restarts: 0.07 MiB a restart as a binary (27.3 to 29.4 MiB resident), none under `mo run` (60.4 to 57.9); the third suite's unwritable category 8 of 8 under `mo run`; the fourth suite's restart category 14 of 14 under both; P6 with two kills through the surface, `/health` back in 102 and 203 ms, 0 of 21,971 acknowledged jobs lost, 36 MB resident after.

**Carried.** The state is still rendered twice per crash (the invariant's value and the report's snapshot are two values), so a crash still writes 27 MiB of stderr at 20,000 jobs and 140 at 100,000. `mo test` keeps every report whole, as before. The one-second restart at 100,000 jobs. The compaction copy per reference. The bench baseline gap.

## Related

- [[erosion-round]]
- [[interpreter-step-32]]
- [[01d-job-queue-change-3]]
- [[roadmap]]
