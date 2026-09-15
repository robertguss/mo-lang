---
title: "Sampling as verification: five regenerations of the queue's board, pre-registered"
created: 2026-09-15
updated: 2026-09-15
type: plan
tags: [verification, agents, research]
sources: [directions/d43-five-measurements.md, plans/control-run-7.md, spec/programs/01-job-queue.md, decisions/decision-log.md]
status: in-progress
---

# Sampling as verification

Measurement 2 of [[d43-five-measurements|direction 43]], decided 15 Sep 2026, 20:50 (decision log): one module of a finished program is regenerated five times by fresh Opus sessions from its stripped spec, a driver feeds all five the same random operation sequences, and every disagreement is read as a defect or a spec hole and compared with what the hidden suite finds. The hypothesis: N implementations of one spec disagree exactly where a defect is, so a spec'd module can be verified by sampling with no suite written. It runs in one pane before [[control-run-8]], while that round's spec and plan are written; if it finds defects, disagreement joins round 8's pre-registration as a fourth oracle on the changed modules. Predictions were written before any session started.

## The module

`Jobq.Board` from round 7's Mo job queue (`../mo-lang-control7-mo/examples/programs/jobq/board.mo`, 698 lines, 10 tests, one property): the queue as a value, with one pure entry point, `decide(board, call, now) : Decision`, that takes a call (create, fetch, list, remove, lease, ack, fail, health) and the clock and returns the board after it, the answer, and the records the store must hold before the answer is sent. It holds the lease and retry logic the decision named: the sweep that puts run-out leases back, the oldest-first order per queue, the attempt count and the dead rule, the race between two workers. It is pure, so five variants can be compared with no socket and no real clock; the process, the store, and the HTTP layer around it are untouched and shared.

## The stripped spec

A script of the lead's (`sampling-as-verification-suite/strip.py`) rewrites `board.mo` to what a fresh agent gets: the module line, the `expose` list, the `use` line, the `intent`, the `never`, every type with its comments, the signature of every exposed function and of every function the tests call, each with its comment and its `requires` and `ensures` lines, the ten tests and the property as written, and no `verified:` line. Every body is gone and every other function is gone, so the decomposition under `decide` is the agent's. Round 7's program spec is in the worktree, and so is the rest of the program: `job.mo` (the job's states and transitions), `queue.mo` (the process that calls `decide`), and the `data/` folders with `jobq.expected`, the program's own check transcript.

## The harness

Before stripping, one worker session writes `examples/programs/jobq/sampler.mo` against the original `board.mo`: a `main` that reads a script of lines `<ms> <worker> <command> [args]`, builds the board from an empty store at a fixed start time, calls `decide` once per line with `now` at start plus the line's milliseconds, and prints one line per call: the outcome and every record the decision writes, jobs through `shown`. The harness is then frozen; the five variants are compared through it. The lead verifies it by playing the demo session's commands through it and reading the outcomes against `jobq.expected`.

## The driver

`sampling-as-verification-suite/sample.py`, the lead's: from a seed, forty operations over two queues, three workers, job ids `j_1` to `j_8`, `max_attempts` 1 to 3, `lease_ms` 100 to 1,000, the clock advancing 0 to 600 ms a line, commands weighted toward lease, ack, and fail. One thousand seeds. For each seed the transcript of the original and of the five variants; a disagreement is the first line where a variant's transcript differs from the majority of the five, and it is grouped with every other seed whose first differing line has the same shape (the same command and the same pair of outcomes). The lead reads each group against the spec and the tests and names it a defect (the spec decides and the minority is wrong), a majority defect (the spec decides and the majority is wrong), or a spec hole (the spec does not decide). The original is not in the vote; its disagreements with the vote are read the same way.

## The ground truth

Round 7's hidden suite (`control-run-7-suite/defects.py`, 121 checks) is run on the whole jobq program with each variant's `board.mo` in place, under `mo run`, `--only` the tests that reach the board (`lifecycle`, `listing`, `expiry`, `race`, `health`). A variant's suite defects are the checks it fails; the original fails none (round 7). A defect the suite finds is *found by sampling* when that variant is in the minority of a disagreement group the lead read as a defect.

## Setup

| what | where |
|---|---|
| worktree | `../mo-lang-sampling`, branch `sampling` from `main`, the round 7 jobq copied in from `../mo-lang-control7-mo` as `examples/programs/jobq/` |
| pane, agents | `w7:p7`; `mo-sample-0` writes the harness, `mo-sample-1` to `mo-sample-5` regenerate, one fresh session each, sequential |
| branches | `sampling-k` from `sampling` after the stripped file is committed; each variant is one branch |
| the brief | "The bodies of `board.mo` are gone; write them so `mo check` and `mo test` on `examples/programs/jobq` are green and `mo run main.mo -- check data/demo data/session.txt` matches `jobq.expected`; touch no other file; commit when green; report loops by cause, wall-clock, and the decisions the spec did not cover" |
| what a session sees | the worktree as it is, this page's name never; the token count of its pane is read before its report (measurement 5) |

## Pre-registered

| prediction | threshold |
|---|---|
| P1, regeneration is feasible | every variant is green within 90 minutes of worker time |
| P2, sampling finds the suite's defects | of the suite defects across the five variants, at least half are found by sampling; if the suite finds none, P2 is unread and P3 decides |
| P3, sampling finds holes | at least two disagreement groups are spec holes, each a row for `01-job-queue.md` or for round 8's change spec |
| P4, the opposite | if the five agree on every seed and the suite finds no defect in any variant, sampling has no signal on a spec'd module of this size and the fourth oracle is dropped from round 8 |

Recorded, not predicted: loops to green by cause per variant, wall-clock, output tokens, tokens read (the pane's count), lines per variant, the number of disagreement groups, and the first line at which each group diverges.

## Result

*(written after the runs)*

## Related
- [[d43-five-measurements]]
- [[control-run-7]]
- [[control-run-8]]
- `spec/design-v0/08-milestone.md`, the measure
