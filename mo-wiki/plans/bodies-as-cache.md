---
title: "Bodies as cache: every program regenerated from its spec, twice, pre-registered"
created: 2026-09-16
updated: 2026-09-16
type: plan
tags: [verification, agents, research]
sources: [directions/d43-five-measurements.md, plans/sampling-as-verification.md, plans/control-run-8.md, decisions/decision-log.md]
status: in-progress
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

*(written after the runs)*

## Related
- [[d43-five-measurements]]
- [[sampling-as-verification]]
- [[control-run-8]]
- [[roadmap]]
