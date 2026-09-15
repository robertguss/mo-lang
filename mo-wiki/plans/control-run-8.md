---
title: "The control run, round 8: the maintenance round, pre-registered"
created: 2026-09-15
updated: 2026-09-15
type: plan
tags: [agents, verification, roadmap]
sources: [plans/control-run-7.md, spec/programs/01-job-queue.md, spec/programs/01b-job-queue-change.md, spec/design-v0/01-premise.md, spec/design-v0/08-milestone.md, decisions/decision-log.md, directions/d43-five-measurements.md]
status: in-progress
---

# The control run, round 8

The experiment the laws were written for. Every program so far was written once and never changed; the contracts, the `never`s, the `invariant`s, and the recipe check exist for the second agent, the one who did not write the program, and that has never been measured. Round 8 hands round 7's three finished job queues ([[control-run-7]]: Mo, Go, Python, 0 defects each under a 121-check hidden suite) to three fresh agents with one changed spec, `spec/programs/01b-job-queue-change.md`: scheduled jobs and retry backoff (a new state, a new route), `attempts` and `max_attempts` renamed `tries` and `max_tries`, and a durability rule that changes (the store must replay the log the old service wrote). Two hidden suites read the result: round 7's for regressions, a new one for defects in the change. The claim under test is the conjunction of chapter 1, reliability at zero dependencies, read on both columns together (Robert, 15 Sep 17:45). Generation one of the erosion round ([[d43-five-measurements|direction 43]], measurement 3); the same change runs on the Elixir program in round 10. The predictions below were written before any worktree was branched; the start time is the first line of the Result.

## The suites

**Regressions:** `control-run-7-suite/defects.py`, unchanged except that it speaks the new field names and the new health key (a copy, `control-run-8-suite/regressions.py`, with `attempts` renamed and `scheduled` accepted in `/health`; nothing else). A regression is a check the round 7 program passed that the changed program fails.

**Defects:** `control-run-8-suite/defects.py`, written by Fable after the three worktrees were branched and kept out of every worktree until the sessions end (the round 7 disclosure: this page describes the suite's categories, so it is written after the branching too). Its categories: the new fields' validation (`delay_ms`, `backoff_ms`, the old names refused); a scheduled job not leased before `run_at` and leased after it, by the clock the service reads, with `/health` and listings agreeing; a fail with backoff scheduling the job, without backoff queueing it, on the last try killing it; a run-out lease with backoff; the retry route on every state; a scheduled job deleted; the scheduled-to-queued move durable under a SIGKILL; **the old log**: a folder the round 7 service of the same implementation wrote, with queued, leased, done, and dead jobs and a torn last line, served by the changed program, every job present with its state, then compacted with no old name left; the race for one job unchanged; and 8 workers under load with backoff on. A defect is a failed check.

## Setup

| worker | worktree | branch | from |
|---|---|---|---|
| Mo | `../mo-lang-control8-mo` | `control8-mo` | `main` after step 30, with round 7's `examples/programs/jobq/` and its sidecar entries copied in from `control7-mo`, verified green under the step 30 toolchain before the session |
| Go | `../mo-lang-control8-go` | `control8-go` | `control7-go`, with `toolchain/`, `examples/`, and `mo-wiki/` removed |
| Python | `../mo-lang-control8-python` | `control8-python` | `control7-python`, the same removed; `mypy` and `ruff` already the project's dev dependencies |

Round 7's worktrees are evidence and are not touched. Agents `mo-r8-mo`, `mo-r8-go`, `mo-r8-python`, one fresh session each, in three panes split from `w7:t1`, each `cd`'d into its worktree before `herdr agent start`. The same brief for all three: the change spec by path, "the tests must pass, the service must keep its durability", commit when green, report loops by cause, wall-clock, and the decisions the spec did not cover. Nothing names this page, the suites, or the other languages. Each pane's token count is read before its report (measurement 5).

**The same-disk rule** (decision log, 15 Sep): the queue is fsync-bound on this disk, about 990 syncs a second, so Go and Python are rerun with Fable's `measure.py` on this disk the same day Mo is, with `MO_CORES` unset, before Mo's speed row is read; no speed number from round 7 is reused. The step 29b binary's 353 pairs a second today against round 7's 981 is why.

## Pre-registered

| prediction | threshold |
|---|---|
| P1, regressions | Mo's changed queue fails no more of round 7's suite than Go's and than Python's |
| P2, defects | Mo's changed queue fails no more of the new suite than Go's and than Python's |
| P3, speed and memory, native, same disk | lease-and-ack pairs a second with 32 workers at least Python's and at least half of Go's; resident memory at 100k jobs at most 3 times Go's and at most Python's plus a quarter |
| P4, the feedback loop | `mo check` plus `mo test` over the changed queue, measured by Fable, under 3 s and faster than `go vet` + `staticcheck` + `go test` and than `mypy --strict` + `ruff` + the tests |
| P5, dependencies | Mo 0 packages and 0 tools; Go 0 and at most 1; Python at least 1 and at least 2 |

**The reading.** Reliability is P1 and P2 together; the conjunction is P1, P2, and P5 together. Mo keeps the reliability claim only if P1 and P2 hold while P5 holds, that is, it matches the checked baselines on regressions and defects while needing none of what they needed; Go with the standard library and one build tool is the comparison that decides (decision log, 15 Sep 17:45). Fewer than Go on P1 plus P2 supports the claim; equal keeps it unproven, and the erosion round's next generations are what can move it; more refutes it for this round. P3 and P4 are read as in round 7 and do not touch the claim. Fable's guesses, recorded so the predictions are not free: regressions Mo 0, Go 0, Python 0 to 1; defects Mo 0 to 1, Go 1, Python 1 to 2, the old log being where a baseline slips (a strict record model refusing the old names) and the scheduled-to-queued write under a kill where any of the three may.

Recorded, not predicted: wall-clock and loops by cause; lines and files changed; **tokens read per correct change** (the pane's input token count at the report, divided by one change; measurement 5) and **first-fix rate per diagnostic** (from the Mo pane's loop log: for each Mo diagnostic seen, whether the next edit made it go away; a diagnostic under 0.7 with ten or more sightings is rewritten); whether a contract, `never`, `invariant`, recipe check, or diagnostic caught a change-induced bug the worker's own tests would not have, in each language with its own checks; which contracts and `never`s the change forced open; the `within:` count after the change; the runtime-surface questions; and, if [[sampling-as-verification]] found defects before this round started, disagreement among regenerations of the changed modules as a fourth oracle, run after the suites and recorded beside them.

## Result

*(the start time, then the tables, written after the sessions)*

## Related
- [[control-run-7]]
- [[sampling-as-verification]]
- [[d43-five-measurements]]
- [[d42-elixir-round]]
- [[01-premise]]
- [[08-milestone]]
- [[roadmap]]
