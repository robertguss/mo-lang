---
title: "The control run, round 9: the small-model round, pre-registered"
created: 2026-09-15
updated: 2026-09-16
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
status: done
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
| M4  | `gemini-3.8-flash`, replaced by `gpt-5.5` through Pi's Codex login (01:10: the Google key in Pi is invalid, `API_KEY_INVALID`; `gpt-5.3-codex-spark` is refused on a ChatGPT account; xAI has no key) | Pi, `--provider openai-codex` | the closed-model row; not small, and the page says so |
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
| M4 gpt-5.5 (Codex) | Go | yes, 01:15 | 6 min by the lead's clock (the brief at 01:09, the commit at 01:15; its report says "about 45 minutes") | 2 (both fixture drift after the rename), first fix right in both | 0 of 121 | 1 of 189 (the same `delay_ms` null; four of four Go changes now) | 97k / 15k |
| M4 gpt-5.5 (Codex) | Mo | yes, 01:23 | 14 min | 13 (MO0101, MO0303 twice, MO0317 twice, own tests 3, the 'held by two workers' `never` after a retry as in round 8, the old-name replay fallback caught by its own replay check, two harness slips), every first fix right | 0 of 121 | 0 of 189 | 200k / 36k |
| M4 gpt-5.5 (Codex) | Python | yes, 01:16 | 7 min by the lead's clock (its report says 55) | 7 failing checks over 4 causes, first fix right in each | 0 of 121 | 0 of 189 | 122k / 18k |
| M1 qwen3.8 27B, local | Mo, Go, Python | **not green at 90 min, all three**: no edit made in 92 minutes (0 files changed in every worktree); it read the program and reasoned in text, 6 shell calls in Mo, 4 in Go, 0 in Python; the three sessions shared one local model, so each waited on the others' prompts | 92 min, stopped | 0 | — | — | 384k / 2.5k, 277k / 2.4k, 280k / 2.0k |
| M5 Haiku 4.5 (Claude Code, `--model haiku`, `/effort medium`) | Go | by its tests, 08:31, 9 min by the lead's clock (its report says "about 30 minutes"); `check.sh` red at the commit (its serve-and-client half still sends `max_attempts`); a 10 MB binary committed with the change | 9 min | 7 by its report (the rename 3, the API names 1, the expectations 2 with one partial fix, the replay 1) | 0 of 121 | 22 of 189 over 6 causes: the `delay_ms` null (five of five Go changes now); a fail with backoff trips its own bolted-on `never` ("a scheduled job is not held by a worker") and the service answers 500; a run-out lease on the last try is scheduled, not dead; the retry route trips "a done or dead job changes state" on every state; a later trip exits the server with code 1, and durable, race, and end fail behind it; the old dead job cannot be retried | 157k in the window at the end, no compaction |
| M5 Haiku 4.5 | Python | by its tests (114), 08:29, 7 min by the lead's clock (its report says "about 15"); `mypy --strict` (2 errors, `bench.py` on the old names), `ruff` (11), and `check.sh` (the expected transcript not regenerated) red at the commit | 7 min | 0 by its report ("correct approach on first attempt") | 0 (134 checks in the paced form) | 18 of 189 over 2 causes: deleting a scheduled job answers 500 and the job stays (4 checks); the retry route answers 500 "internal error" on every state, so a retried job is never queued, not after a kill, not from the old log (14) | 131k, no compaction |
| M5 Haiku 4.5 | Mo | by its tests (seven modules pass), 08:31, 9 min by the lead's clock (its report says "~90 minutes"); the corpus transcript `jobq.expected` not regenerated (66 differing lines: the new names, the `scheduled` count); `mo build` green | 9 min | 1 by its report ("one loop with multiple interconnected compilation errors": the parameter limit, `case` exhaustiveness, `Option`, JSON field naming); the pane had scrolled past its work before it could be read | 0 of 121 under both runtimes | 28 of 189 under both runtimes, over 4 causes: the old names `attempts` and `max_attempts`, a negative, string, fractional, null, or boolean `delay_ms` or `backoff_ms`, and a client-given `run_at` all accepted with 201 (11 checks); a scheduled job is never moved to queued once its `run_at` has passed, so it is never leased, never recounted, not after a restart, and 100 of 100 jobs sit scheduled under load (15); one round of the race check (1, cause unread); the old log compacted with an old name left in it (1) | 168k, no compaction |

**After five models (16 Sep, 08:45 local).** Haiku 4.5 is the first model whose change is defective in all three languages, and the first Mo row wrong at the change's centre: a scheduled job is never moved to queued once due, the feature the change is about, and the old names are accepted at create. Its three sessions took 7 to 9 minutes by the lead's clock and each stopped at its own tests: none was green by the brief's standard (Go's `check.sh`, Python's `mypy`, `ruff`, and `check.sh`, Mo's corpus transcript, all red at the commit), and each report's wall-clock is wrong by a factor (Mo says 90 minutes for 9). Go's bolted-on `never`s caught the model's bugs the way a bolted-on check does: the service answers 500, and once, exits 1. In Mo nothing states "a due job is never left scheduled", so nothing caught it, the row already written for the language page. The counts: Mo 28 checks over 4 causes, Go 22 over 6, Python 18 over 2. The setup: three Claude Code sessions in workspace `w4B`, the toolchain binary the deepseek and gpt-5.5 rows used (`5ec04ddd`; kimi's was the build from earlier that night, `fda805e5`), the brief from `r9-brief.sh`; the suite outputs and the panes of every row of the round are under `control-run-9-suite/results/`.

**After three models (16 Sep, 01:30 local).** gpt-5.5 through Codex matched Opus on the Mo change (0 and 0) in 14 minutes against Opus's 34, with the same `never` false positive after a retry that cost Opus two loops (one here), and its own replay check caught the one real slip (the old-name fallback). Its Go change carries the one defect every Go change carries (four of four now), its Python change is under the suites. So after three models the Mo row's defects come from the two open-weights models only, and the run-out-with-backoff miss is theirs alone.

**After two models (16 Sep, 01:10 local).** Six sessions, six green. Reliability moved with the model on the Mo side only: both small models' Mo changes carry the same defect Opus's did not (a run-out lease with `backoff_ms` is put back as scheduled and never handed out once its backoff has passed, 204), deepseek's a second (`run_at` from the client accepted), while their Go changes carry exactly Opus's one defect and their Python changes none. P1 holds. P2 fails for both models: Mo's defects are above Python's (1 and 2 against 0) and, for deepseek, above Go's. P4 holds for both (Mo 11 and 12 loops against Go's 4 and 7). P3 is unread until the loop logs are read against the diffs; nothing in either report says a law stopped a bug, and deepseek's `requires` trip was its own test's wrong lease length. P5 waits on M1. The time column: kimi 15, 35, and 97 minutes; deepseek 11, 14, and 17. The pane column: Mo cost kimi 500k input tokens and three compactions of a 128k window, the Go change 139k; the Mo program is the one the model has never seen, and the loop rate says the diagnostics carried it (first fix right in 21 of 23 loops across the two Mo sessions).

## Reading, against the predictions (16 Sep, 02:45 local)

Five of five models run: three cloud models in Pi, the local 27B, and Haiku 4.5 through Claude Code (added 16 Sep, 08:45); the Opus-in-Pi baseline has no key. Every cloud model reached green in every language by its own tests; the local model made no edit.

| prediction | threshold | result | held |
|---|---|---|---|
| P1, reliability moves with the model | one model's Mo change has a regression or a defect | kimi 1 cause, deepseek 2 (both miss the run-out lease with backoff), gpt-5.5 0, Haiku 4 causes and 28 checks; regressions 0 everywhere | yes |
| P2, the claim holds per model | Mo's defects no more than Go's and Python's | kimi: Mo 1, Go 1, Python 0; deepseek: Mo 2, Go 1, Python 0; gpt-5.5: Mo 0, Go 1, Python 0; Haiku: Mo 28 checks over 4 causes, Go 22 over 6, Python 18 over 2 | no for the two open-weights models and for Haiku (by checks; by causes Mo sits between Go and Python), yes for gpt-5.5 |
| P3, the laws catch something | a contract, `never`, `invariant`, or diagnostic stops a change-induced bug | nothing in twelve reports says so; gpt-5.5's own replay check caught its old-name fallback slip, the same `never` false positive after a retry cost it and Opus a loop; deepseek's `requires` trip was its own test's wrong lease; Haiku's Go `never`s tripped under the hidden suite, after the session, on the bugs it shipped | no |
| P4, the tax | Mo takes more loops than Go | kimi 11 to 4, deepseek 12 to 7, gpt-5.5 13 to 2; Haiku 1 to 7 by its own reports, the Mo pane unreadable | yes for four models, no for Haiku by its own count |
| P5, the floor | the local 27B does not reach green in Mo, and does in Go or Python | green in none | half: the floor is below Go and Python too |

**What it says.** Reliability moves with the model on the Mo side and only there. Every Go change, Opus's included, carries the same `delay_ms` null defect, a reading of one spec sentence that no model caught; every Python change is at 0; the Mo changes go 0 (Opus, gpt-5.5), 1 (kimi), 2 (deepseek), and the defect the two open-weights models share is a scheduling case the change added (a run-out lease with `backoff_ms` put back as scheduled and never handed out once due) that the checks do not state and the tests they wrote did not reach. So the language's checks did not carry the weaker models past the mistake they made, and the diagnostics did carry them to green: first fix right in 21 of 23 loops for kimi and deepseek in Mo, every loop for gpt-5.5, in a language no model has seen. The time column: Mo cost the open-weights models 97 and 17 minutes against Go's 15 and 11; gpt-5.5 did the Mo change in 14 minutes, Opus in 34. The local 27B could not do the task in any language in this harness: it read the program and thought, and never wrote, which is the floor direction 41 asked for and it sits below Go and Python as well. The row for the language page: the checks that would have caught the open-weights models' miss are a `never` on the lease path ("a due job is never left scheduled") that none of the programs states; that is a spec row, not a law. Haiku 4.5 adds the row between the open-weights models and the local 27B: it writes in every language in under ten minutes and the change is wrong in every language, most wrong in Mo by check count (28, 22, 18) and least by cause in Python (4, 6, 2); the Mo miss is the change's core, the due job never queued, which no law states and no test it wrote reached, and the diagnostics carried it to a program that compiles in one reported loop, not to one that is right. So the floor for Mo sits between Haiku and gpt-5.5, where it sits for Go and Python too: at this size the language does not change whether the change is right, only which checks are missing.

## Related

- [[d41-small-model-round]]
- [[control-run-8]]
- [[control-run-7]]
- [[model-bakeoff]]
- [[roadmap]]
