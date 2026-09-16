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

Started 15 Sep 2026, 23:21 local, on the Mac, Fable alone. A setup slip recorded first: the change spec is not in round 7's branches, and the brief named it by a relative path; the Go session found it in the main branch's history with `git show` (identical to the file), the Mo and Python sessions were told the absolute path at 23:41, and `r9-brief.sh` now gives it. The Pi sessions ran with the Ollama app started by Fable (its server was down at first, the three first prompts errored and were re-sent at 23:23). Every session's pane is saved to the scratchpad and its `REPORT.md` is in its worktree. The Python suites had to run one category at a time with a 35 s pause between (`control-run-9-suite/paced-python.sh`): the Python service closes every connection, and on macOS the client runs out of ephemeral ports to one destination inside the suite (`EADDRNOTAVAIL`), which never happened on the Linux VM; the checks are the same.

| model | language | green | wall-clock | loops (own) | regressions | defects | tokens (↑ in, ↓ out, per Pi) |
|---|---|---|---|---|---|---|---|
| M3 kimi-k3 | Go | yes, 23:39 | about 15 min | 4 | 0 of 121 | 1 of 189 (`delay_ms` null accepted as absent, 201; Opus's Go had the same one) | 139k / 78k, one compaction |
| M3 kimi-k3 | Python | yes, 23:57 | about 35 min | 7 failing checks over 6 causes, first fix right in 5 | 0 of 121 | 0 of 189 | 184k / 90k, one compaction |
| M2 deepseek-v4-flash | Go | yes, 00:34 | about 11 min | 7 (2 build, 2 vet, 2 test, 1 staticcheck), every first fix right | 0 of 121 | 1 of 189 (the same `delay_ms` null as Opus's and kimi's Go) | 177k / 102k |
| M2 deepseek-v4-flash | Python | yes, 00:37 | about 14 min | 5, every first fix right | 0 of 121 | 0 of 189 | 141k / 83k |
| M3 kimi-k3 | Mo | **not green at 90 min** (the pre-registered rule); green at 01:00, 97 min after the brief (its own count 75 min from its first baseline run; the first 18 min lost to the Ollama outage and the missing spec path), recorded as a flagged extra | 97 min | 11 (MO0102, MO0101, MO0104, a `return` in a nothing-function, own tests 3, a `--sim` loop under the frozen clock, and one two-edit fix), first fix right in 10 | 0 of 121 | 1 cause, 2 checks of 189 (a run-out lease with backoff is not handed out by a lease once its backoff has passed: 204) | 500k / 192k, three compactions past 128k |
| M2 deepseek-v4-flash | Mo | yes, 00:58 | 17 min | 12 (MO0001, MO0303 twice, MO0306 twice, MO0101, MO0104, MO0206, MO0403, MO0317, own tests 3, `mo fmt`), first fix right in 11 | 0 of 121 | 2 causes, 3 checks of 189 (`run_at` given by the client accepted with 201; the run-out lease with backoff not handed out once due, as kimi's) | 352k / 137k |


**After two models (16 Sep, 01:10 local).** Six sessions, six green. Reliability moved with the model on the Mo side only: both small models' Mo changes carry the same defect Opus's did not (a run-out lease with `backoff_ms` is put back as scheduled and never handed out once its backoff has passed, 204), deepseek's a second (`run_at` from the client accepted), while their Go changes carry exactly Opus's one defect and their Python changes none. P1 holds. P2 fails for both models: Mo's defects are above Python's (1 and 2 against 0) and, for deepseek, above Go's. P4 holds for both (Mo 11 and 12 loops against Go's 4 and 7). P3 is unread until the loop logs are read against the diffs; nothing in either report says a law stopped a bug, and deepseek's `requires` trip was its own test's wrong lease length. P5 waits on M1. The time column: kimi 15, 35, and 97 minutes; deepseek 11, 14, and 17. The pane column: Mo cost kimi 500k input tokens and three compactions of a 128k window, the Go change 139k; the Mo program is the one the model has never seen, and the loop rate says the diagnostics carried it (first fix right in 21 of 23 loops across the two Mo sessions).

## Related

- [[d41-small-model-round]]
- [[control-run-8]]
- [[control-run-7]]
- [[model-bakeoff]]
- [[roadmap]]
