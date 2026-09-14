---
title: "The control run, round 6: logstat and jobq, the baselines with their checks bolted on, pre-registered"
created: 2026-09-14
updated: 2026-09-14
type: plan
tags: [agents, research, roadmap]
sources: [plans/control-run-5.md, plans/control-run.md, plans/program-1.md, plans/program-2.md, spec/programs/01-job-queue.md, spec/programs/02-log-analyzer.md, research/concepts/empirical-validation-plan.md, spec/design-v0/08-milestone.md]
status: queued
---

# The control run, round 6

The round that can confirm or reject chapter 8's null hypothesis: that an agent does as well in an existing language with Mo's checks bolted on. Rounds 1 to 5 ran the baselines bare; this round bolts the checks on (Go with `go vet`, `staticcheck`, and a contracts library; Python under a `uv init` project with `mypy --strict`, `ruff`, and `pydantic`) and adds a second task, the job queue, whose `never`s and durability are where Mo's checks are meant to earn their keep. Two tasks, three languages, three fresh sessions in parallel, each doing both tasks in order. The thresholds below were written before any session started (14 Sep 2026, the time is in the Result section's first line).

Since round 5: steps 22 to 26 (the derived deadline, the runtime surface, the authority hole, a handle in `state`, `delay:`, the one-line `if` as a value, `state` and `old` as field names) and program 5. The Mo briefs are [[program-2]] and [[program-1]] word for word; the baseline brief is [[control-run]] with the amendments below.

## Setup

| worker | worktree | branch | removed before start |
|---|---|---|---|
| Mo | `../mo-lang-control6-mo` | `control6-mo` | `examples/programs/logstat/`, `examples/programs/logstat.expected` and its `# run:` lines, `examples/programs/jobq/` and its `.expected` files |
| Go | `../mo-lang-control6-go` | `control6-go` | `experiments/control-run/go/` |
| Python | `../mo-lang-control6-python` | `control6-python` | `experiments/control-run/python/` |

Worktrees from `session-05` on the exe.dev VM (Linux x86_64, 4 cores, 15 GB; the earlier rounds ran on Robert's Mac, so wall-clock compares within this round, not to round 5). Agents `mo-r6-mo`, `mo-r6-go`, `mo-r6-python`, each `cd`'d into its worktree before `herdr agent start`. The branches are evidence and are not merged. Tools on the machine before the start: Zig 0.16.0, Go 1.26.5, `staticcheck` 2026.2.1 (`go install`), `uv`, `mypy` 2.3.1 and `ruff` 0.16.1 as `uv` tools; `pydantic` goes into the Python project's own environment. The pane's token count is read before each report.

## The baselines' amendments to the brief

Word for word [[control-run]], with these changes, given to the Go and Python agents in their prompt:

1. Two tasks in order, `logstat` from `spec/programs/02-log-analyzer.md` in `experiments/control-run/<lang>/logstat/`, then `jobq` from `spec/programs/01-job-queue.md` in `experiments/control-run/<lang>/jobq/`; a final message per task with the measurements.
2. The checks are required, not "if available": Go runs `go vet` and `staticcheck` clean and uses a contracts library (one from `pkg.go.dev` of the agent's choosing, or a `contract` package of its own of at most 40 lines with `Require`, `Ensure`, and `Invariant` that fail with the condition's text, the choice said in the report); Python is a `uv init` project, `mypy --strict` and `ruff check` clean, `pydantic` models for every JSON shape and every validated input. The standard-library rule bends only for these: the contracts library and `pydantic`.
3. Reading the `jobq` spec outside Mo: a `never` is an assertion checked on every state change plus a test that tries to break it; an `invariant` is a check after every operation on the queue; `requires`/`ensures` are the contracts library's calls with a test each; `within:` is a timeout on every call that can wait; `--sim 100 --faults` is a test that runs the queue under 100 seeds of injected file and socket failures with the durability rules checked after each; the store recipe is any append-only log that replays; the 1,200 idle connections test stands as written. The `within:` count is reported as the count of timeout literals, chosen or derived.
4. Measured, per task, in the final message: loops to green by cause (a check the language or a tool made, a test mistake, a real bug, tooling), wall-clock, functions with median and max lines, program plus test lines, which checks caught a real bug the agent's own tests did not, and every point where the language or a library forced a decision the spec did not make.

## Pre-registered

Four predictions. All four must hold for the round to count as "held"; any one failing makes it "mixed", and the reading says which. The null hypothesis is stated by P3: if it fails in the baselines' favour, the hypothesis stands and the page says so plainly.

| prediction | threshold | the last number |
|---|---|---|
| P1, wall-clock | Mo at most 1.5 times Go, summed over both tasks | 1.28 on logstat (round 5); jobq has no baseline |
| P2, loops by cause | Mo has no loop from a shape law and at most one from a grammar form or a misleading diagnostic across both tasks; test-mistake loops count against no language | round 5: 0 law, 1 form; round 4: 0 law, 4 form |
| P3, the checks (the null hypothesis) | on `jobq`, Mo's bolted-in checks (`never`, `invariant`, a contract, `--sim`) catch at least one real bug the worker's own tests did not, and the baselines' bolted-on checks (vet, staticcheck, the contracts library; mypy, ruff, pydantic) catch no more real bugs than Mo's; a type error the language would have refused anyway does not count | program 1: two `never`s tripped under `--sim` during the build; rounds 1–5: no baseline check caught a bug in code |
| P4, size | Mo's program plus test lines at most 0.65 of Go's on `jobq` | logstat: 831 to 1,552 (0.54) |

Recorded for every worker besides: whether it wrote the language directly, the pane's token count at the end of each task, the `within:` (timeout) count with its chosen and derived columns, and the Q16 ledger for Mo (a law that blocked the program).

## Result

(Written after the run.)

## Reading, against the predictions

(Written after the run.)

## Related
- [[control-run-5]]
- [[control-run]]
- [[program-1]]
- [[program-2]]
- [[empirical-validation-plan]]
- [[roadmap]]
