---
title: "The control run, round 2: logstat again on today's toolchain"
created: 2026-09-13
updated: 2026-09-13
type: plan
tags: [agents, research, roadmap]
sources: [plans/control-run.md, spec/programs/02-log-analyzer.md]
status: done
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

## Result (13 Sep 2026, 09:25 to 09:37)

| | Mo round 1 | **Mo round 2** | Go round 2 | Python round 2 |
|---|---|---|---|---|
| wall-clock | 25.5 min | **11.8 min** | 8.2 min | 7.9 min |
| loops to green (code) | 2 | **0** | 0 | 1 |
| loops to green (tooling) | 6 | **0** | 2 (staticcheck, gofmt) | 1 (mypy hints) |
| functions | 78 | 4 modules, median **3** lines, max 12 | 46, median 10, max 31 | median 5, max 19 |
| program + test lines | 1,174 | **791** | 1,386 | 983 |
| checks that caught a real bug | 2 | 0 (nothing fired) | 0 | 0 (own test wrong) |
| stdlib gaps hit | 9 | 5 | 5 | 0 |
| verified by Fable | with the file law lifted | **yes, as is** | yes | yes |

Verification: Mo's 30 tests pass from the four source files, `mo run` over the fixture matches the expected output, and the worker derived its expected files from an independent Python calculation rather than from `mo run`. Go and Python pass their checks and tests.

**Reading.** Mo's time halved and every failure mode of round 1 is gone: zero failed runs, no toolchain workaround, no lifted law. It is still about 45 percent slower than Go and Python, and the worker's report says where the time went: `mo fmt` produced awkward shapes it reworked three times, and five stdlib rows were missing (`sort_by` descending, two-value `min`/`max`, a streaming read). Mo's functions are a third the length of Go's. No language's checks caught a bug this round, because there were none to catch: the spec is now well understood by the model after three readings across rounds, which is itself a finding about spec-driven work. The remaining gap is toolchain ergonomics, and it is measured in single-digit minutes.

## Related
- [[control-run]]
- [[program-2]]
- [[roadmap]]
