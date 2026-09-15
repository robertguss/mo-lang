---
title: "The control run, round 10: the Elixir round, pre-registered"
created: 2026-09-16
updated: 2026-09-16
type: plan
tags: [runtime, verification, agents, roadmap]
sources: [directions/d42-elixir-round.md, plans/control-run-7.md, plans/control-run-8.md, spec/programs/01-job-queue.md, spec/programs/01b-job-queue-change.md, spec/design-v0/01-premise.md, decisions/decision-log.md]
status: in-progress
---

# The control run, round 10

The BEAM is chapter 1's null hypothesis and it has only ever been argued on paper ([[d42-elixir-round|direction 42]], Robert, 15 Sep evening). This round puts it in a pane: one fresh Opus session writes round 7's job queue in Elixir from the same spec, with dialyzer, credo, and ExUnit as its checks, and a second fresh session makes round 8's change to it from the same change spec. Both hidden suites read the result beside Mo's, Go's, and Python's rows from rounds 7 and 8. Fable brought the round forward from "after round 9" to the night of 15–16 Sep, since round 9 waits on Robert's Pi provider logins and this one waits on nothing (decision log, 16 Sep). Predictions were written before the session started.

## What decides

If Elixir matches Mo on the suites and the runtime rows, Mo's delta over the BEAM is only what is left: static types, unforgeable capabilities, a deadline on every wait, one static binary, no ecosystem; each of those then has to be measured on its own or dropped. If Elixir falls behind on reliability or on the runtime rows, the language layer earns its place. Dependencies are read as chapter 1 says: every Hex package at run time plus every tool, against Mo's zero.

## Setup

| what | where |
|---|---|
| worktree | `../mo-lang-control10-elixir`, branch `control10-elixir` from `main` at `a2d220a`, with `toolchain/`, `examples/`, and `mo-wiki/` removed and the two spec pages at `spec/` |
| the program | `experiments/control-run/elixir/jobq/`, a Mix project; Elixir 1.18.5 on OTP 27 through `mise`, installed 16 Sep 00:10 for this round |
| agents | `mo-r10-elixir` writes the program from `spec/01-job-queue.md`; after Fable's verification and the round 7 suite, `mo-r10-elixir-change`, a fresh session, makes `spec/01b-job-queue-change.md` |
| the brief | round 7's Mo brief in shape: the spec by path, the checks named (`mix compile --warnings-as-errors`, `mix dialyzer`, `mix credo --strict`, `mix test`), a `check.sh`, a `bench/` client, the wall-clock and loops reported, the decisions the spec did not cover listed; then round 8's brief for the change |
| the suites | `control-run-7-suite/defects.py` on the first program; `control-run-8-suite/regressions.py` and `defects.py` (with `--old-serve` the first program) on the changed one; `oracle4.py` with an Elixir log writer once the log's shape is known |
| measure | `control-run-8-suite/measure.py` on the changed program, alone on the disk, in the same session as Go's and Python's round 8 numbers were taken; Mo's row is round 8's binary |

## Pre-registered

| prediction | threshold |
|---|---|
| P1, reliability, round 7's suite on the first program | Elixir 0 or 1 defects of 121 (Mo, Go, Python were 0, 0, 0) |
| P2, reliability, round 8's suites on the changed program | regressions 0; defects at most 1 (Mo 0, Go 1, Python 0) |
| P3, speed and memory, native | pairs a second at 32 workers between Python's 325 and Mo's 1,420; memory at 100k jobs above Go's 81 MiB and below 300 MiB |
| P4, the feedback loop | dialyzer, credo, and the tests over the finished program above 10 s cold; `mix test` alone under 5 s |
| P5, dependencies | at least 3 Hex packages counting dialyzer and credo as tools, and `jason` or the standard library's JSON at run time |
| P6, the runtime rows | the kill under load loses no acknowledged write; a crashed queue process is restarted by its supervisor and the service keeps answering, where Mo's changed queue stops answering ([[control-run-8]], the outage) |

**The reading.** P6 is the row that decides the BEAM question: if Elixir's supervision restores service where Mo's program did not, that is the null hypothesis winning on the one row the runtime claims as its own, and the language page has to say why Mo's `restart: :never` and the send-then-wait pattern were the natural choice for a Mo program. P1 and P2 read the reliability claim as in round 8. P3 to P5 are recorded against the same columns.

## Result

*(written after the sessions)*

## Related
- [[d42-elixir-round]]
- [[control-run-8]]
- [[control-run-7]]
- [[roadmap]]
