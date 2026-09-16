---
title: "The control run, round 9: the small-model round, pre-registered"
created: 2026-09-15
updated: 2026-09-15
type: plan
tags: [agents, research, roadmap]
sources:
  [
    directions/d41-small-model-round.md,
    plans/control-run-7.md,
    plans/control-run-8.md,
    spec/programs/01b-job-queue-change.md,
    decisions/decision-log.md,
  ]
status: in-progress
---

# The control run, round 9

[[d41-small-model-round|Direction 41]], Robert's call of 15 Sep (locked): the
same task and hidden suites as a finished round, run by much smaller and cheaper
models, open-weights ones among them, every model in the Pi harness so the
harness is the same in every row. Fable's reading there: reliability and loops
are the two columns that move with the model, and a weaker model makes the
mistakes the checks exist to catch, so this is the stronger test of the
reliability claim, not the weaker one.

## The task

Round 8's change ([[01b-job-queue-change]]: scheduled jobs, backoff, the retry
route, the `tries` rename, the old log still opening) on round 7's three
finished job queues, exactly as round 8 gave it to Opus. Chosen over writing
round 7's queue from the spec because it is bounded (Opus took 15 to 34
minutes), it has two hidden suites already (`control-run-8-suite/regressions.py`
and `defects.py --old-serve`), and it is the maintenance task the laws were
written for: the second agent, who did not write the program. A session that is
not green after 90 minutes of wall-clock is stopped and scored as not green.

## The models

From Robert's Pi logins on the Mac (ollama cloud, Google, OpenAI Codex, xAI; no
Anthropic key in Pi, so the small Claude runs through Claude Code). Fable's
pick, 15 Sep, 23:00 local, for a spread of size and openness:

| row | model                               | harness                      | why                                                                                   |
| --- | ----------------------------------- | ---------------------------- | ------------------------------------------------------------------------------------- |
| M1  | `qwen3.8:27b-mlx`, local on the Mac | Pi, `--provider ollama`      | the smallest, open weights, runs on the machine; the row direction 41 asked for first |
| M2  | `deepseek-v4-flash:cloud`           | Pi, `--provider ollama`      | open weights, mid-size, cheap                                                         |
| M3  | `kimi-k3:cloud`                     | Pi, `--provider ollama`      | open weights, large; Robert's Pi default                                              |
| M4  | `gemini-3.8-flash`                  | Pi, `--provider google`      | small closed model                                                                    |
| M5  | Haiku 4.5                           | Claude Code, `--model haiku` | the small Claude, the one row not in Pi                                               |

The Opus-in-Pi baseline direction 41 wanted is unmet: Pi on this Mac has no
Anthropic login. Round 8's Opus rows (Claude Code) stand as the baseline, with
that caveat on every comparison.

## Setup

Per model, three worktrees branched again from round 7's programs, never from
round 8's: `../mo-lang-r9-<m>-mo` on `r9-<m>-mo` from `control7-mo`, and the
same for `go` and `python`; the step 30 toolchain binary copied into the Mo one.
Agents `mo-r9-<m>-mo`, `mo-r9-<m>-go`, `mo-r9-<m>-python` (Herdr names are
lowercase), one fresh session each, in three panes split from the mo-lang
workspace, each `cd`'d into its worktree before `herdr agent start`. The brief
is round 8's word for word (`control-run-9-suite/r9-brief.sh`): the change spec
by path, the tests must pass, the service must keep its durability, commit when
green, report the wall-clock, the loops by cause, and the decisions the spec did
not cover, to `REPORT.md`. Nothing names this page, the suites, or the other
languages. One model at a time, three panes; the suites run by Fable after each
model's three sessions, the speed rows measured alone on the disk afterwards.

## Pre-registered

Written before any session starts.

| prediction                           | threshold                                                                                                                                                                                                                            |
| ------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| P1, reliability moves with the model | at least one model's Mo change has a regression or a defect under the suites, where Opus had 0 and 0                                                                                                                                 |
| P2, the claim holds per model        | for every model that reaches green in all three languages, Mo's defects plus regressions are no more than Go's and no more than Python's                                                                                             |
| P3, the laws catch something at last | in at least one Mo session a contract, a `never`, an `invariant`, or a diagnostic other than a syntax error stops a change-induced bug the model's own tests would have passed (read from the loop log and the diff, as round 8 did) |
| P4, the tax                          | in every model's row, Mo takes more loops than Go, as it did for Opus (9 to 8)                                                                                                                                                       |
| P5, the floor                        | the smallest model (M1) does not reach green in Mo within 90 minutes, and does in at least one of Go and Python                                                                                                                      |

Recorded, not predicted: wall-clock, loops by cause, first-fix rate per
diagnostic, tokens read where the harness shows them, lines changed, and every
session's "decisions the spec did not cover".

## Result

(to be written)

## Related

- [[d41-small-model-round]]
- [[control-run-8]]
- [[control-run-7]]
- [[model-bakeoff]]
- [[roadmap]]
