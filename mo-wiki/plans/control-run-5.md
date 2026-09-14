---
title: "The control run, round 5: logstat after step 21 and program 1, pre-registered"
created: 2026-09-14
updated: 2026-09-14
type: plan
tags: [agents, research, roadmap]
sources: [plans/control-run-4.md, research/concepts/empirical-validation-plan.md, plans/program-2.md, plans/control-run.md, deep-dives/research-agenda-2026-09-response.md]
status: in-progress
---

# The control run, round 5

The first pre-registered round, as [[empirical-validation-plan]] asked: the thresholds below were written before any session started (14 Sep 2026, 01:20). Same spec, same model, three fresh sessions in parallel in worktrees from which the earlier implementations are removed, briefs word for word [[program-2]] and [[control-run]], so the round compares with round 4, the timing round. The toolchain since round 4: step 21 (green threads, three diagnostics for round 4's loops, `mo fix` for the one-line `if`) and program 1's evidence. Nothing in the briefs changed; the bolted-on-checks arm for the baselines (Go with a contracts library, Python with `pydantic`) waits for a round with a second task, since changing the baselines' briefs would break the comparison this round exists for.

## Setup

| worker | worktree | branch | removed before start |
|---|---|---|---|
| Mo | `../mo-lang-control5-mo` | `control5-mo` | `examples/programs/logstat/` |
| Go | `../mo-lang-control5-go` | `control5-go` | `experiments/control-run/go/` |
| Python | `../mo-lang-control5-python` | `control5-python` | `experiments/control-run/python/` |

Agents `mo-r5-mo`, `mo-r5-go`, `mo-r5-python`. The branches are evidence and are not merged.

## Pre-registered

Three predictions, decided before the run; all three must hold for the round to count as "held", any one failing makes it "mixed", and the reading says which.

| prediction | threshold | round 4 |
|---|---|---|
| P1, wall-clock | Mo at most 1.5 times Go | 1.73 |
| P2, loops to green | Mo at most Go's plus 2 | 5 to 1 |
| P3, the laws | no loop from a shape law, and none from the three forms step 21 gave diagnostics for | 0 law loops, 3 form loops |

Two new columns, recorded for every worker: loops by cause (a law, a grammar form, a diagnostic, a test mistake, a real bug) and whether the worker wrote its language directly or wrote a generator for it (from the pane and the commits). Tokens: the pane's final status line per session (Claude Code's own count), amortized preamble not separated this round.

## Result

Filled in after the run.

## Related
- [[control-run-4]]
- [[empirical-validation-plan]]
- [[program-2]]
- [[control-run]]
- [[roadmap]]
