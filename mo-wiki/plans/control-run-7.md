---
title: "The control run, round 7: reliability, speed, the loop, and dependencies, pre-registered"
created: 2026-09-14
updated: 2026-09-14
type: plan
tags: [agents, research, roadmap]
sources: [plans/control-run-6.md, spec/design-v0/08-milestone.md, spec/programs/01-job-queue.md, spec/programs/02-log-analyzer.md, decisions/decision-log.md]
status: queued
---

# The control run, round 7

The first round on Robert's measure (chapter 8, Session 6): reliability first, then how fast the program runs, how fast the loop is, and how many dependencies it needs. Agent time and loops are recorded, not predicted. Same two tasks and three languages as [[control-run-6]], after step 27 (the file law gone, `state`/`result`/`old` as names, a `never` that reads values at rest, the `\u{...}` escape). The thresholds below were written before any session started; the start time is the first line of the Result.

## The hidden defect suite

`defects.py`, written by Fable on 14 Sep before the round and kept out of every worktree (in the lead's scratchpad until the round starts, then committed under `mo-wiki/plans/control-run-7-suite/`). It starts an implementation's `serve`, then runs 121 checks against the spec: authorization, 14 malformed bodies, the routes and their statuses, the whole lifecycle, listing filters and the 100 cap, payload round-trips (Unicode, quotes, a newline), a lease running out and a stale ack, 32 workers racing for one job and 32 racing to ack it, 8 workers under load, 1,200 quiet connections and a half-sent request, a 2 MiB body, a SIGKILL with live and run-out leases, a SIGKILL under load (every 201 and every acked 200 answered before the kill must be there after), a torn last line in the log, and health. A defect is a failed check.

Run after the fact on round 6's three programs to calibrate it, 14 Sep 16:10 UTC: **Mo 0 defects, Python 0, Go 1** (a token with a space accepted) of 121, every one durable under the kill. So the suite as written separates little between careful implementations; a prediction that Mo has the fewest is a prediction that it keeps that.

## Setup

| worker | worktree | branch | removed before start |
|---|---|---|---|
| Mo | `../mo-lang-control7-mo` | `control7-mo` | `examples/programs/logstat/`, `examples/programs/jobq/`, their README rows and `.mo.ids` entries |
| Go | `../mo-lang-control7-go` | `control7-go` | `experiments/control-run/go/`, and the two Mo programs as above |
| Python | `../mo-lang-control7-python` | `control7-python` | `experiments/control-run/python/`, and the two Mo programs as above |

Worktrees from `session-05` after step 27, on the exe.dev VM. Agents `mo-r7-mo`, `mo-r7-go`, `mo-r7-python` in panes `w7:p7`, `w7:p8`, `w7:p9`. The Mo programs are removed from every worktree this time, so no baseline copies a fixture. The briefs are round 6's with two amendments: the Python checkers are project dev dependencies (`uv add --dev mypy ruff`, run through `uv run`), and each worker reports the wall-clock of its own check-and-test command on the finished program.

## Pre-registered

| prediction | threshold | round 6 |
|---|---|---|
| P1, reliability | Mo's jobq has no more defects under the hidden suite than Go's and than Python's | 0, 1, 0 after the fact |
| P2, speed and memory, native jobq | lease-and-ack pairs a second with 32 workers at least Python's and at least half of Go's; resident memory at 100k jobs at most 3 times Go's and at most Python's plus a quarter | 399 / 858 / 377; 192 / 73 / 191 MiB |
| P3, the feedback loop | `mo check` plus `mo test` over the finished jobq, measured by Fable, under 3 s and faster than `go vet` + `staticcheck` + `go test` and than `mypy --strict` + `ruff` + the tests | unmeasured |
| P4, dependencies | Mo 0 third-party packages and tools; Go at most 1; Python at least 2 | 0 / 1 / 3 |

All four must hold for "held"; any one failing makes it "mixed". Recorded, not predicted: wall-clock and loops by cause per task, lines, functions, tokens, the `within:` count, whether a check caught a bug, the runtime-surface questions.

## Result

(Written after the run.)

## Reading, against the predictions

(Written after the run.)

## Related
- [[control-run-6]]
- [[interpreter-step-27]]
- [[program-1]]
- [[program-2]]
- [[roadmap]]
