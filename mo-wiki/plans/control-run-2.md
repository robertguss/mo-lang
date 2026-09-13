---
title: "The control run, round 2: logstat again on today's toolchain"
created: 2026-09-13
updated: 2026-09-13
type: plan
tags: [agents, research, roadmap]
sources: [plans/control-run.md, spec/programs/02-log-analyzer.md]
status: in-progress
---

# The control run, round 2

Round 1 (13 Sep, 00:18) put Mo at 25.5 minutes against Go's 12.9 and Python's 8, with every minute of Mo's loss traced to the toolchain: no multi-module programs, no stdlib, a slow interpreter. Steps 7 through 12b fixed all of it. Round 2 reruns the identical experiment on today's toolchain: same spec, same model, three fresh sessions in parallel, in worktrees from which the round 1 implementations have been deleted so nothing is copied.

## Setup

| worker | worktree | branch | removed before start |
|---|---|---|---|
| Mo | `../mo-lang-control2-mo` | `control2-mo` | `examples/programs/logstat/` |
| Go | `../mo-lang-control2-go` | `control2-go` | `experiments/control-run/go/` |
| Python | `../mo-lang-control2-python` | `control2-python` | `experiments/control-run/python/` |

Briefs are word for word [[program-2]] and [[control-run]]; the Mo worker writes to `examples/programs/logstat/` as before. The branches are evidence and are not merged; the numbers and the Mo program's gaps are what round 2 produces.

## Result

Filled in by Fable when the three finish.

## Related
- [[control-run]]
- [[program-2]]
- [[roadmap]]
