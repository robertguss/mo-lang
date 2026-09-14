---
title: "The control run, round 4: logstat after steps 17–20, the timing round"
created: 2026-09-13
updated: 2026-09-13
type: plan
tags: [agents, research, roadmap]
sources: [plans/control-run-3.md, plans/control-run.md, spec/programs/02-log-analyzer.md, deep-dives/outside-review-2026-09-13-response.md]
status: in-progress
---

# The control run, round 4

Round 3 (13 Sep, 13:58) lost its wall-clock column to the machine sleeping, and put Mo at 9 loops to green against Go's 2 and Python's 1, six of Mo's loops syntax diagnostics. Steps 17 to 20 reworded those diagnostics, fixed the two toolchain bugs the run found, and changed how servers are written. Round 4 reruns the identical experiment: same spec, same model, three fresh sessions in parallel, in worktrees from which the earlier implementations have been deleted. It is the round the laws are re-evaluated against ([[outside-review-2026-09-13-response]]).

## Setup

| worker | worktree | branch | removed before start |
|---|---|---|---|
| Mo | `../mo-lang-control4-mo` | `control4-mo` | `examples/programs/logstat/` |
| Go | `../mo-lang-control4-go` | `control4-go` | `experiments/control-run/go/` |
| Python | `../mo-lang-control4-python` | `control4-python` | `experiments/control-run/python/` |

Briefs are word for word [[program-2]] and [[control-run]]; agents `mo-r4-mo`, `mo-r4-go`, `mo-r4-python`. The branches are evidence and are not merged.

## Result

Pending.

## Related
- [[control-run-3]]
- [[control-run]]
- [[program-2]]
- [[roadmap]]
