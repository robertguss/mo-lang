---
title: "The control run, round 8: the maintenance round, pre-registered"
created: 2026-09-15
updated: 2026-09-17
type: plan
tags: [agents, verification, roadmap]
sources: [plans/control-run-7.md, spec/programs/01-job-queue.md, spec/programs/01b-job-queue-change.md, spec/design-v0/01-premise.md, spec/design-v0/08-milestone.md, decisions/decision-log.md, directions/d43-five-measurements.md]
status: done
---

# The control run, round 8

The experiment the laws were written for (generation one of the [[erosion-round]]; the same change ran in Elixir as [[control-run-10]]). Every program so far was written once and never changed; the contracts, the `never`s, the `invariant`s, and the recipe check exist for the second agent, the one who did not write the program, and that has never been measured. Round 8 hands round 7's three finished job queues ([[control-run-7]]: Mo, Go, Python, 0 defects each under a 121-check hidden suite) to three fresh agents with one changed spec, `spec/programs/01b-job-queue-change.md`: scheduled jobs and retry backoff (a new state, a new route), `attempts` and `max_attempts` renamed `tries` and `max_tries`, and a durability rule that changes (the store must replay the log the old service wrote). Two hidden suites read the result: round 7's for regressions, a new one for defects in the change. The claim under test is the conjunction of chapter 1, reliability at zero dependencies, read on both columns together (Robert, 15 Sep 17:45). Generation one of the erosion round ([[d43-five-measurements|direction 43]], measurement 3); the same change runs on the Elixir program in round 10. The predictions below were written before any worktree was branched; the start time is the first line of the Result.

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

Recorded, not predicted: wall-clock and loops by cause; lines and files changed; **tokens read per correct change** (the pane's input token count at the report, divided by one change; measurement 5) and **first-fix rate per diagnostic** (from the Mo pane's loop log: for each Mo diagnostic seen, whether the next edit made it go away; a diagnostic under 0.7 with ten or more sightings is rewritten); whether a contract, `never`, `invariant`, recipe check, or diagnostic caught a change-induced bug the worker's own tests would not have, in each language with its own checks; which contracts and `never`s the change forced open; the `within:` count after the change; the runtime-surface questions; and the fourth oracle in the form [[sampling-as-verification]] earned it (15 Sep, 22:10): the three workers' "decisions the spec did not cover" lists are read for inputs the suites do not send, and each such input is played through all three programs after the suites; a random driver over the API found nothing in five regenerations and is not run.

## Result

The sessions started 15 Sep 2026, 22:22 UTC, in panes `w7:pE`, `w7:pC`, `w7:pD`, from the worktrees above, the suites committed under `control-run-8-suite/` after the branching and never in a worktree. Go finished at 22:37, Python at 22:38, Mo at 22:57; each was asked to write its report to `REPORT.md` in its worktree (the panes were too narrow to read; Go's came from the pane and its tokens from `/context`, Python's `/context` was not readable before its session was closed, so its token count is unread). Verified by Fable: Mo `mo test` on all seven modules (25, 15, 12, 8, 7, 4, 7 tests), `mo check --recipe` 8 of 8, the check transcript byte-for-byte, a `mo build` binary; Go `go vet`, `staticcheck`, `go test`, `check.sh`; Python `mypy --strict`, `ruff`, 173 `unittest` tests, `check.sh`. Both suites were run on the three changed programs, Mo's under `mo run` and as a binary. One check of the defect suite was amended after Go's run and before the reading (`runout`, its comment says why: it took one of two readings the spec allows; the amended check was rerun on all three).

### On Robert's measure

| | Mo, native | Go | Python |
|---|---|---|---|
| regressions, round 7's suite (121 checks) | 0 (0 under `mo run`) | 0 | 0 |
| defects, the new suite (189 checks) | 0 (0 under `mo run`) | 1 | 0 |
| creates a second, 100k jobs of 100 bytes | 2,246 | 929 | 770 |
| lease-and-ack pairs a second, 1 worker / 32 workers | 266 / 1,420 | 419 / 428 | 317 / 325 |
| resident memory at 100k jobs / after the pairs | 113 / 150 MiB | 81 / 88 MiB | 189 / 190 MiB |
| restart on that log, to `/health` | 2.31 s (42 MB) | 0.71 s (36 MB) | 1.32 s (39 MB) |
| feedback loop, the checks and tests over the changed program | 0.81 s (`mo check` and `mo test` over seven modules, best of three) | 14.4 s (`go test -count=1`; 0.25 s with Go's test cache warm) | 7.5 s |
| third-party at run time / tools at build time | 0 / 0 | 0 / 1 (`staticcheck`) | 1 (`pydantic` and its four) / 2 (`mypy`, `ruff`) |

Go's one defect: `delay_ms: null` and `backoff_ms: null` are taken as absent and answered `201` where the spec says a value that is not an integer is `400` (Go's decision 6 chose it; Mo and Python answer `400`).

### Recorded, not predicted

| | Mo | Go | Python |
|---|---|---|---|
| wall-clock to green | 34 min 08 s | 15 min | 15 min 50 s |
| loops to green | 9 | 8 | 6 |
| loops by cause | MO0303 (the six-parameter law) 1; the "held by two workers" `never` re-keyed after a retry reset `tries`, 2; own wrong test assertions 2; MO0002 and MO0403, 2; MO0317 stale lines, 2; one queue test under `--sim` faults abandoned after 4 | a build flag 1; the rename's cascade through tests 2; expected shapes 1; a patch that missed after `gofmt` 1; a missing import 1; own wrong expectations 2 | `ruff` line length 4 (one first fix missed two of five); `mypy` 1; own wrong test 1 |
| first fix right | 7 of 9 causes | 8 of 8 | 5 of 6 |
| files, lines changed | 9 files, +959 −233 (the sidecar apart) | 18 files, +1,032 −247 | 23 files, +1,099 −164 |
| tokens read per correct change (the pane's context at the report) | about 347k (messages 323k) | about 180k (messages 156k) | unread |
| a check that caught a change-induced bug the worker's tests would not have | none; the `never` cost two loops as a false positive | none | none |
| contracts and `never`s the change forced open | the "two workers at once" `never` re-keyed to `(number, tries, instant)`; the create arguments folded into a `Making` struct under the six-parameter law; one queue test left passing only without faults | the "done or dead never changes state" `never` split in two; an `invariant` added for a retry | `_LEGAL` gained five edges; the "queued has tries left" contract widened to scheduled |
| the old log | replayed through the board and re-encoded; `data/compact/jobq.log` committed in the new shape | `testdata/v1/jobq.log` written by the round 7 binary before any code change | `tests/fixtures/round7/jobs.log` written by the unchanged program before any code change |

**The fourth oracle** (`control-run-8-suite/oracle4.py`): fourteen inputs taken from the three decision lists, played through all three. Eleven agree. Three do not: `delay_ms: 0.0` (a whole float) is `201` in Mo and `400` in Go and Python; a log record carrying both `attempts` and `tries` is read by Mo and refused at open by Go and Python; and a log record with a queued job whose `attempts` equal its `max_attempts` is refused at open by Go (its replay invariant) and by Python (its invariant), while Mo opens it, answers `/health`, and on the first lease its queue process crashes on `job.mo`'s `requires` in `leased` and **the service stops answering every request**, `/health` included. That last is the same state measurement 2 found in the round 7 program, now in the changed one, and it is worse than a crash: the acceptor is alive and nothing behind it is. The state is unreachable by the API and by any log the old or new service writes; it is what a foreign or hand-edited log holds. It is recorded here as a fourth-oracle finding, not as a suite defect, since the suites do not send it, and it is the strongest row against Mo in this round: the two baselines' bolted-on invariants refuse the folder, Mo's contract turns it into an outage.

**The outage, probed** (16 Sep, 00:05, after Robert said to run it): the same log served under `mo run` and as a binary, `/health` answered, one lease crashed the queue process, and every request after it timed out, `/health` and creates included, with no restart in the next twelve seconds and the listener still accepting. Chapter 3 explains it as written: the queue is a `:never` child, a send to it is dropped with a `Dropped` event, and the worker answers a request by sending `Want` and waiting for a `Done` message, a wait with no deadline. The runtime did what the spec says; the program never handles a down queue, and the deadline law cannot see a wait written as a message pattern. Decision-log row, 16 Sep.

## Reading, against the predictions

| prediction | threshold | round 8 | held |
|---|---|---|---|
| P1, regressions | Mo no more than Go and than Python | 0 / 0 / 0 | yes |
| P2, defects | Mo no more than Go and than Python | 0 / 1 / 0 | yes |
| P3, speed and memory, same disk | pairs at 32 workers at least Python's and half Go's; memory at most 3× Go's and Python's plus a quarter | 1,420 pairs against 428 and 325; 113 MiB against 81 (1.4×) and 189 | yes |
| P4, the feedback loop | under 3 s and faster than both | 0.81 s against 14.4 and 7.5 | yes |
| P5, dependencies | Mo 0 and 0; Go 0 and at most 1; Python at least 1 and 2 | 0/0 · 0/1 · 1/2 | yes |

**Held on all five, measured on this disk the same night, Go and Python rerun with nothing else running.**

1. **The conjunction holds, thinly.** Mo matched the checked baselines on regressions and beat Go by one defect at zero packages and zero tools. The one defect that separates them is a null taken as absent, a reading of one sentence of the spec, and the count on the other side is the fourth oracle's outage, which no suite sent. Read as chapter 1 asks, reliability at zero dependencies survives round 8; read as evidence that the laws made the second agent safer, there is none yet: no contract, `never`, `invariant`, recipe check, or diagnostic caught a change-induced bug in any language, for the fourth program and the third round running, and Mo's `never` cost two loops as a false positive when a retry reset the key it was written on.
2. **The maintenance tax is real and it is Mo's.** The same change took the Mo maintainer 2.2 times Go's wall-clock, 1.9 times Go's tokens, and 9 loops to Go's 8 and Python's 6; three of the nine were laws (the six-parameter limit, a string across lines, a capability outside a test) and two were the toolchain's MO0317 on dependents, the loop measurement 2 had already named. Three of the nine were the maintainer's own wrong tests, the same as Go's two and Python's one. Nothing in the loop count is a bug the laws caught.
3. **The runtime row that matters is the outage.** A process crash on a `requires` inside the queue took the whole service down without a restart or a refusal. Whether that is the program's supervision (the acceptor's asks with no fallback) or the runtime's is the first question for the pause; a `requires` that trips on replayed data should refuse the folder at open, as the spec now says for records that are not jobs and as both baselines do.
4. **Speed and the loop.** At 32 workers the Mo binary makes 1,420 pairs a second on this disk, 3.3 times Go's 428, because step 30's fsync pool covers many changes with one sync where Go and Python sync each; at one worker it is the slowest of the three (266 against 419 and 317), the price of the ask across schedulers on every request; creates run at 2.4 times Go's; the restart on the 100k log is the slowest, 2.3 s against 0.7. The loop is 0.81 s against Go's 14.4 s with its test cache bypassed (0.25 s warm) and Python's 7.5 s.
5. **Measurement 5's columns exist now.** Tokens read per correct change: Mo about 347k, Go about 180k, Python unread. First-fix rate per diagnostic over rounds 8 and measurement 2: MO0101 5/5, MO0501 4/4, MO0212 2/2, MO0201 2/2, MO0317 6/7, MO0303 1/1, MO0002 1/1, MO0403 1/1; nothing under 0.7, nothing at ten sightings yet.
6. **What changes in the next generation.** The erosion round continues from this program with the second sealed change; the fourth oracle keeps its form; the old-log rule is extended to say what a record in an impossible state does; and the Elixir round takes this change with this suite.

## Related
- [[control-run-7]]
- [[sampling-as-verification]]
- [[d43-five-measurements]]
- [[d42-elixir-round]]
- `spec/design-v0/01-premise.md`, the thesis
- `spec/design-v0/08-milestone.md`, the measure
- [[roadmap]]
