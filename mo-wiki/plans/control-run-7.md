---
title: "The control run, round 7: reliability, speed, the loop, and dependencies, pre-registered"
created: 2026-09-14
updated: 2026-09-14
type: plan
tags: [agents, research, roadmap]
sources: [plans/control-run-6.md, spec/design-v0/08-milestone.md, spec/programs/01-job-queue.md, spec/programs/02-log-analyzer.md, decisions/decision-log.md]
status: done
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

The sessions started 14 Sep 2026, 16:40 UTC, from worktrees branched at `ba87a5b` (step 27 merged), the suite committed to `control-run-7-suite/defects.py` after the branching. Panes `w7:p7`, `w7:pA`, `w7:pB`. Go finished at 17:17, Python at 17:20, Mo at 17:56; no sleep. Verified by Fable in each worktree: Mo `zig build test` 185 of 185 with both programs in the corpus, `mo fmt --check` clean, logstat and `jobq check` run by hand; Go `go vet`, `staticcheck`, `go test`, and `check.sh` clean for both tasks; Python `uv run mypy --strict`, `uv run ruff check`, 73 and 114 `unittest` tests, and `check.sh` clean for both, its checkers dev dependencies of each project.

**A disclosure.** The Mo worker reported that before starting it read this page down to its Result heading, which describes the suite's categories (not its code); the Go and Python workers were pointed at round 6's page and did not report reading this one. So P1 for Mo is a prediction its worker knew the shape of. The next round writes the suite's description after the worktrees are branched, as the suite itself was.

### On Robert's measure

| | Mo, native | Go | Python |
|---|---|---|---|
| **defects under the hidden suite** (121 checks) | **0** | **0** | **0** |
| creates a second, 100-byte payloads, 8 producers (Fable's client) | 1,320 | 954 | 769 |
| lease-and-ack pairs a second, 1 worker (Fable's client) | 329 | 412 | 292 |
| lease-and-ack pairs a second, 32 workers (Fable's client) | **981** | 478 | 467 |
| resident memory at 100k jobs (Fable's client) | 150 MiB | 76 | 189 |
| restart on a 36–38 MB log, to `/health` (Fable's client) | 3.7 s | 0.7 | 1.0 |
| the worker's own numbers: pairs at 32 workers; memory at 100k; replay of 1M records | 1,091; 299 MiB; 15.3 s (interpreted 704; 287; 64.8) | 469; 70 MiB; 4.8 s | 333–441; 193 MiB; 5.2 s |
| **feedback loop**, one run over the finished jobq, cold caches, Fable's timing | **0.38 s** (`mo check` + `mo test`, 7 modules) | 18.7 s (`go vet` + `staticcheck` + `go test`) | 8.7 s (`mypy --strict` + `ruff` + `unittest`) |
| **third-party at run time / as tools** | **0 / 0** | 0 / 1 (staticcheck) | 1 (pydantic and its four) / 2 (mypy, ruff) |

Fable's client is the same script for all three (keep-alive connections, 8 producers, then 1 and 32 workers for 10 s each, then a SIGTERM and a restart), so those rows compare; the workers' own loaders differ (Mo's opened a connection a request and measured 299 MiB after its load, twice Fable's reading), so their rows are given, not compared.

### Recorded, not predicted

| | Mo | Go | Python |
|---|---|---|---|
| wall-clock, logstat / jobq / both | 15 / 60 / 74.6 min | 8 / 28 / 36 | 12.3 / 27 / 39.1 |
| loops to green, logstat + jobq, by cause | 21: 10 language checks (`MO0214`, three `case`-arm statements, nesting depth, one name per declaration, declaration order, fixtures only in tests, an unread lambda parameter), 7 test mistakes, 2 real bugs (one caught by a store `ensures`, one by a test), 2 tooling | 4: 1 compiler (an undefined `err`), 3 test mistakes, 1 tooling | 10: 6 tool findings (ruff style, mypy inference), 2 test mistakes, 1 real bug (a dead `never`, caught by its own test), 1 tooling |
| jobq lines, program + tests | 3,208 (2,157 + 672, non-blank) | 3,655 (1,775 + 1,880) | 3,144 (1,545 + 1,599) |
| jobq functions: count, median, max | 216, 6, 25 | 105 + 88, 10 / 14, 46 / 58 | 119 + 160, 6 / 6, 27 / 26 |
| a check that caught a real bug the worker's tests would not have | none (the `ensures` fired first, the test would have caught it) | none | none |
| performance bugs found by the load runs, caught by no check or test | 3: a store table copied each flush, a queue list copied each create (the worker's), and a map write that copies the whole map (the toolchain's) | 0 | 1: an fsync per run-out lease, 11.7 s on a restart with 10,000 |
| `within:` count, jobq | 17, all chosen, 0 derived (the recipe's signatures carry no deadline; a flush has no asker) | 6, one derived | 6, two derived |
| invariants kept | 0 of 7 (all refused before a message can break them) | 4 kept, 5 out | 7 kept, 3 of them untrippable |
| the Q16 ledger | empty; the laws cost loops, blocked nothing | — | — |
| stdlib gaps, toolchain bug notes | 6 gaps (`Fs.list` cannot tell a file from a folder; no thousands separator; a lambda cannot leave a parameter unread; no `seconds` on an integer; `Option` has no `map`; the fixture clock is frozen so no test can watch a lease run out), 4 bug notes (a `never` still reads a `var` copy when the second write sits inside an `if`; setting or removing a map key copies the whole map, 22.7 s for 2,000 writes at 80k entries; resident memory grows far past the regions and `MemoryInfo` does not see it; a `reduce` with a tuple accumulator copies it each step) | 0, 0 | 0, 0 |
| output tokens, the transcript's summed usage | 1.47 M over 459 turns | 1.29 M over 97 | 1.26 M over 155 |
| wrote the language directly | yes | yes | yes |

## Reading, against the predictions

| prediction | threshold | round 7 | held |
|---|---|---|---|
| P1, reliability | Mo's defects at most Go's and Python's | 0, 0, 0 | **yes**, with the disclosure above: all three level, none found |
| P2, speed and memory | pairs at 32 workers at least Python's and half Go's; memory at most 3 times Go's and Python's plus a quarter | 981 to 467 and 478; 150 MiB to 76 and 189 (on Fable's client; the worker's own 299 MiB would have failed the memory half) | **yes** |
| P3, the loop | `mo check` + `mo test` under 3 s and faster than both | 0.38 s to 18.7 and 8.7 | **yes** |
| P4, dependencies | Mo 0, Go at most 1, Python at least 2 | 0, 1, 3 | **yes** |

**Held, all four.** The first round on Robert's measure, read plainly:

1. **Reliability is level.** The hidden suite found nothing in any of the three finished programs; all three keep every acknowledged write through a kill under load and start on a torn log. Round 6's programs did the same. Two rounds now say that with a spec at this altitude and a model at this level, a job queue comes out correct in Mo, Go, and Python alike, and Mo's built-in checks did not need to fire to get there. The suite is 121 checks of the spec's own rules; a harder suite, or a program whose invariants are the point (the ledger), is where a difference would show if one exists.
2. **Mo's runtime is now ahead on throughput and behind on restart.** Group commit, which the Mo worker chose and the others did not, doubles Mo's 32-worker throughput over Go's single-fsync-per-change; native Mo also creates fastest. Memory sits between Go and Python. The restart is five times Go's: replay is the runtime's slowest path (15 s for 1M records native to Go's 4.8) and the worker found the map write that copies the whole map, which is a toolchain bug to fix, not a program's.
3. **The loop is Mo's clearest win**: 0.38 s to check and test seven modules against 8.7 and 18.7 s, cold. This is the number the agent-loop claim rests on and it had never been a prediction.
4. **Dependencies are what the design says.** Mo needs nothing; Go one tool; Python three packages and tools plus pydantic's four transitive ones.
5. **Agent time is what Robert said it would be.** Mo took twice Go's time and 21 loops to Go's 4; ten of Mo's loops were the language's checks, seven the worker's test mistakes. It is a recorded column now, and it says the language is still unfamiliar and its checks still cost more than they catch on this program.
6. **The toolchain notes are the round's real yield.** Four bug notes (a map write copying the whole map is the one that matters; the `never` rule's `if` gap is step 27's decision 7 meeting a program) and six gaps. The readiness bar for program 7 (a program that finishes with none) is not close.

**What changes.** A step for the four bug notes and the six gaps, the map write first. The suite's description written after the branching next time. The closure audit over this Mo jobq, as the reply to the outside review asked. Then program 6.

## Related
- [[control-run-6]]
- [[interpreter-step-27]]
- [[program-1]]
- [[program-2]]
- [[roadmap]]
