---
title:
  "The erosion round: change 2 to four programs, generation two, pre-registered"
created: 2026-09-16
updated: 2026-09-16
type: plan
tags: [agents, research, roadmap]
sources:
  [
    directions/d43-five-measurements.md,
    plans/control-run-8.md,
    plans/control-run-10.md,
    spec/programs/01c-job-queue-change-2.md,
    plans/interpreter-step-31.md,
  ]
status: in-progress
---

# The erosion round, generation two

[[d43-five-measurements|Direction 43]] §3: Mo's laws hold a program's quality
across generations of fresh maintainers, Go and Python drift. Round 8 was
generation one (three languages) and round 10 brought Elixir to the same point.
Generation two is [[01c-job-queue-change-2]], sealed on 16 Sep from round 8's
outage: the folder checked at open, a failing request contained with a `503` and
the service still answering, `GET /queues`, `jobq verify`. Four fresh Opus
sessions (medium effort), one per language, on branches from each program's
generation-one state; the Mo maintainer gets the step 31 toolchain and its spec
(`Reply(T)`, the deferred reply), since chapter 10 §1 says that is how a
batching queue answers an `ask` without losing the deadline.

## Setup

| language | worktree                                        | from                            | toolchain                                                                                                  |
| -------- | ----------------------------------------------- | ------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| Mo       | `../mo-lang-erosion2-mo`, branch `erosion2-mo`  | `control8-mo` at `07d1322`      | step 31's `mo`, chapter 3 and the stdlib table with `Reply(T)`, `processes/deferred-reply.mo` committed in |
| Go       | `../mo-lang-erosion2-go`, `erosion2-go`         | `control8-go` at `a003067`      | Go 1.27.1, staticcheck                                                                                     |
| Python   | `../mo-lang-erosion2-python`, `erosion2-python` | `control8-python` at `3a8ed96`  | uv, mypy, ruff                                                                                             |
| Elixir   | `../mo-lang-erosion2-elixir`, `erosion2-elixir` | `control10-elixir` at `89ed4c9` | Elixir 1.18 on OTP 27 by `mise.toml`                                                                       |

Agents `mo-e2-mo`, `mo-e2-go`, `mo-e2-python`, `mo-e2-elixir` in workspace
`w4A`. The brief is round 8's: the change spec by absolute path (it is not in
the worktrees), the tests must pass, the service must keep its durability,
commit when green as `jobq: change 2`, the report to `REPORT-change-2.md`.
Nothing names this page, the suites, or the other languages. The third hidden
suite is written by Fable after the sessions start and kept out of every
worktree: the unwritable folder under load, the ill-formed record at open and
under `verify`, `/queues`, and the `503` rules; the fourth oracle is rewritten
from the four decision lists. P6 (`control-run-10-suite/p6.py`, adapted to each
service) runs on every program that has a process to kill: the Mo binary's queue
process cannot be killed from outside, so the Mo probe is round 8's, the
impossible record at the first lease, which change 2 turns into a refusal at
open, and a `Fs.fixture`-free real folder made unwritable under load.

## Pre-registered

| prediction                                | threshold                                                                                                                                                                                                                                                 |
| ----------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| P1, regressions                           | Mo 0 under round 8's suites (regressions and change 1's defects); each baseline at most 1                                                                                                                                                                 |
| P2, defects under the third suite         | Mo's count no more than each baseline's                                                                                                                                                                                                                   |
| P3, the service answers through a failure | after the folder is made unwritable under load, every response is `2xx` on disk, `4xx`, or `503`, `/health` never moves on a `503`, and writes resume without a restart: Mo and Elixir pass; at least one of Go and Python fails a check in this category |
| P4, the fourth oracle                     | the decision lists yield at least one input that breaks at least one program; not Mo's                                                                                                                                                                    |
| P5, the tax                               | the Mo maintainer takes more loops than the Go maintainer, as in rounds 8 and 9                                                                                                                                                                           |
| P6, the deferred reply                    | the Mo maintainer uses `Reply(T)` for the queue's answer (read from the diff); if it does not, the reason in its decision list is a row for chapter 10                                                                                                    |

Recorded, not predicted: wall-clock, loops by cause, first-fix rate per
diagnostic, lines changed, tokens read, the decision lists.

## Result

(to be written)

## Related

- [[d43-five-measurements]]
- [[control-run-8]]
- [[control-run-10]]
- [[01c-job-queue-change-2]]
- [[interpreter-step-31]]
- [[roadmap]]
