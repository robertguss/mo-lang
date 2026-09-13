---
title: "The control run, round 3: logstat after the formatter fixes and HTTP"
created: 2026-09-13
updated: 2026-09-13
type: plan
tags: [agents, research, roadmap]
sources: [plans/control-run-2.md, plans/control-run.md, spec/programs/02-log-analyzer.md]
status: in-progress
---

# The control run, round 3

Round 2 (13 Sep, 09:25) put Mo at 11.8 minutes against Go's 8.2 and Python's 7.9, with the rest of the gap traced to `mo fmt`'s line breaking and five stdlib rows. Step 14 fixed all of it. Round 3 reruns the identical experiment on the toolchain after steps 14 to 16: same spec, same model, three fresh sessions in parallel, in worktrees from which the round 2 implementations have been deleted so nothing is copied.

## Setup

| worker | worktree | branch | removed before start |
|---|---|---|---|
| Mo | `../mo-lang-control3-mo` | `control3-mo` | `examples/programs/logstat/` |
| Go | `../mo-lang-control3-go` | `control3-go` | `experiments/control-run/go/` |
| Python | `../mo-lang-control3-python` | `control3-python` | `experiments/control-run/python/` |

Briefs are word for word [[program-2]] and [[control-run]]; the Mo worker writes to `examples/programs/logstat/` as before. Agents `mo-r3-mo`, `mo-r3-go`, `mo-r3-python`. The branches are evidence and are not merged; the numbers and the Mo program's gaps are what round 3 produces.

## Result

Pending.

## Related
- [[control-run-2]]
- [[control-run]]
- [[program-2]]
- [[roadmap]]
