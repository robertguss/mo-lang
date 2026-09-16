---
title: "Bodies as cache: every program regenerated from its spec, twice, pre-registered"
created: 2026-09-16
updated: 2026-09-16
type: plan
tags: [verification, agents, research]
sources: [directions/d43-five-measurements.md, plans/sampling-as-verification.md, plans/control-run-8.md, decisions/decision-log.md]
status: done
---

# Bodies as cache

Measurement 1 of [[d43-five-measurements|direction 43]], decided by Robert on 15 Sep 2026, 20:40: all six programs, two runs each. The hypothesis: if the spec altitude is real, function bodies are regenerable from what a reader is meant to read, so a program's spec completeness is the fraction of it that comes back correct when every body is deleted and a fresh agent writes them again. [[sampling-as-verification]] gave the first number, 1.0 for one module of the round 7 queue. This page runs the same on whole programs, started the night of 15–16 Sep while Robert sleeps, on Fable's decision. Predictions were written before any session started.

## What a session gets

The program's folder in `examples/programs/<name>/` with every `.mo` file rewritten by `bodies-as-cache-suite/strip-program.py`: the `# run:` headers, module, expose, and use lines, `intent`, every `never`, every type, every `process` and `supervisor` block with its state, invariants, and message lines, every function's signature with its comment and its `requires` and `ensures` lines, top-level and inside a process, and every test, test-rejects, and property block as written; every body is `# body gone; regenerate` and the `verified:` lines are gone. The data folders, the `.expected` transcripts, the program's spec page under `mo-wiki/spec/programs/`, and the rest of the corpus are in the worktree as they are. Nothing names this page.

## The brief

"Every function body in `examples/programs/<name>/` is gone; write them all, and any private helper you need, so that `mo check` and `mo test` are green on every module, every `# run:` line at the top of `main.mo` prints its `.expected` file byte for byte, and `mo test --write` has rewritten the `verified:` lines. Touch no other program. Commit when green with subject '<name> regenerated'. Report the wall-clock, the loops by cause with whether the first fix worked, and a numbered list 'Decisions the spec did not cover'."

## The oracles

For every program: the program's own tests as kept (the regenerator may not change them), the `.expected` transcripts, `mo check --recipe` where the program implements a recipe, and Fable's own probes on real inputs (the check scripts, a socket client). For `jobq`, round 7's hidden suite (`control-run-7-suite/defects.py`, 121 checks) on the whole program under `mo run`, which the original passes at 0. For `logstat`, the round 6 and 7 fixtures. A program's completeness is the fraction of its oracle checks the regeneration passes; a regeneration that never goes green within two hours of worker time is 0 for that run.

## Setup

| what | where |
|---|---|
| worktrees | `../mo-lang-cache-A` and `../mo-lang-cache-B`, branches `cache-A` and `cache-B` from `main` at `a2d220a`, the step 30 toolchain's binary copied in |
| order | logstat, kv, notes, jobq, ledger, agent; run A and run B of one program at the same time in two panes, then the next program |
| agents | `mo-cache-a-<name>`, `mo-cache-b-<name>` (Herdr names are lowercase), one fresh session each |
| the stripped state | committed on each branch before its session as `<name> stripped to its spec` |

## Pre-registered

| prediction | threshold |
|---|---|
| P1 | logstat, kv, notes, and jobq come back at completeness 1.0 in both runs |
| P2 | the ledger comes back above 0.8 in both runs |
| P3 | the agent program is the lowest, below the ledger, in at least one run |
| P4 | two runs of one program differ from each other where they differ from the original, that is, a hole shows as a disagreement |

Recorded, not predicted: wall-clock and loops by cause per run, lines regenerated, the context tokens at the report, and the decision lists, which feed the fourth oracle as in round 8.

## Result

Run 15–16 Sep 2026, 23:49 to 02:31 UTC, on Fable's decision while Robert slept, two panes, ten fresh Opus sessions. Robert stopped the night at the ledger (02:20: "when they finish I want to pause and then have you continue on my mac"), so the agent program's two runs are the Mac session's. Every run was verified by Fable with `bodies-as-cache-suite/verify-program.sh` (every module's tests, every `# run:` line against its `.expected`), and jobq's two with round 7's hidden suite under `mo run`. The ten reports are in `bodies-as-cache-suite/reports/`.

| program | lines stripped of | run A: time, loops, oracles | run B: time, loops, oracles | completeness |
|---|---|---|---|---|
| logstat | 769 → 564 | 13 min, 2, 8 of 8 | 11 min, 1, 8 of 8 | 1.0, 1.0 |
| kv | 1,619 → 1,170 | 15 min, 2, 10 of 10 | 14 min, 1, 10 of 10 | 1.0, 1.0 |
| notes | 2,160 → 1,513 | 16 min, 0, 12 of 12 | 17 min, 3, 12 of 12 | 1.0, 1.0 |
| jobq | 3,057 → 2,135 | 26 min, 5, 15 of 15 and the suite 121 of 121 | 25 min, 4, 15 of 15 and 121 of 121 | 1.0, 1.0 |
| ledger | 4,450 → 3,068 | 42 min, 9, 19 of 19 | 47 min, 6, 19 of 19 | 1.0, 1.0 |
| agent | 4,551 → 3,196 (283 bodies) | 34 min, 10 (first fix right in 10), 24 of 24 | 30 min, 11 (first fix right in 10), 24 of 24 | 1.0, 1.0 |
| logstat, the stronger form: tests deleted too (`strip-program.py --no-tests`, 769 → 319 lines) | run C: 13 min, its own tests and 8 of 8 transcripts | the original 31 tests spliced onto its bodies: 23 pass, 8 fail (main 6/8, parse 5/6, report 3/7, stats 9/10) | 0.74 under the original tests, 1.0 under the transcripts |

Ten regenerations, ten at completeness 1.0: every test kept, every transcript byte for byte, and jobq's 121 hidden checks, twice. No test in any program ever had to be changed. Every loop was fixed by its first edit; the causes were the same shape laws and diagnostics measurement 2 and round 8 saw (MO0101, MO0102, MO0403 `Time.fixture()` outside a test in four of ten runs, MO0212, MO0303, MO0307, MO0409, MO0314), a `mo fmt` pass, and, in the ledger, one convergent mistake: both runs rewrote the kept test helper `call` to compare a retry by its key alone, and both found it by the same kept test, so the test held where the helper's comment did not. Context tokens were not readable in the four-way split panes and are unrecorded; the worker reports carry their own reading lists.

**The agent program, and the stronger form (16 Sep, 00:10 local, on the Mac).** Two fresh Opus sessions (medium effort) regenerated the agent program's 283 bodies from its intent, types, processes, signatures with contracts, and tests in 34 and 30 minutes, at completeness 1.0 on all 24 oracle checks (every module's tests, six transcripts byte for byte), 10 and 11 loops, every first fix right. Twelve of twelve regenerations are now at 1.0. The stronger form, decided by Fable the same night: logstat with its 31 tests deleted as well as its bodies (769 lines to 319: intent, types, `never`s, signatures with contracts), one Opus session, 13 minutes, green on its own tests and on all eight transcripts; then Fable spliced the original 31 tests onto the regenerated bodies inside the module tree: 23 pass, 8 fail. The eight are the rules the tests carried that the spec's signatures and intent do not state: the widths of the text report's columns and its blank lines (four in `report.mo`), `parse_line("")` naming field 1 (one), a record at exactly `since` counted (one), `.log` alone not a log name and `.logs` not either (one), and a slow directory's problem (one). So the completeness of the spec alone is 0.74 on this program under its tests and 1.0 under its transcripts: the transcripts are the program's real fixture, and the tests are where the spec's open choices were written down. Row for the spec: those eight choices belong in `02-log-analyzer.md`.

## Reading, against the predictions

| prediction | threshold | result | held |
|---|---|---|---|
| P1 | logstat, kv, notes, jobq at 1.0 in both runs | all four, both runs | yes |
| P2 | the ledger above 0.8 in both runs | 1.0 and 1.0 | yes |
| P3 | the agent program lowest, below the ledger | 1.0 and 1.0, 34 and 30 minutes, below the ledger's 42 and 47; not lowest | no: the sixth program is as complete as the first five |
| P4 | two runs differ where they differ from the original | no run differed from the original on any oracle; the holes showed as the workers' decision lists, not as failures | not testable at 1.0 |

**What it says.** For five programs of 769 to 4,450 lines, what a reader is meant to read (the intent, the types, the processes, the signatures with their contracts, and the tests) is enough for a fresh agent to write the bodies back correctly, first time, in 11 to 47 minutes, with every kept oracle passing. Bodies are cache for these programs: the spec altitude is real, and the supply-chain claim that a recipe can be regenerated rather than downloaded has its first evidence. The number is 1.0 because the tests were kept; the direction's stronger form, tests deleted too, is the next run, and the agent program, the one whose check depends on arrival order and whose spec is the loosest, is the one predicted to fall. Cost: about four hours of two panes for five programs, both runs.

**Rows.** For the language page: `Time.fixture()` outside a test (MO0403) cost a loop in four of ten runs and every fix was the same, so the diagnostic is right and the rule is learned only at the point of use, as run B of logstat said. For the spec: the ledger's idempotency key is compared by the whole request, and the test helper's comment should say so, since two independent regenerations read it as the key alone.

## Related
- [[d43-five-measurements]]
- [[sampling-as-verification]]
- [[control-run-8]]
- [[roadmap]]
