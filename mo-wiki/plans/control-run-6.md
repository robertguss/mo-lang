---
title: "The control run, round 6: logstat and jobq, the baselines with their checks bolted on, pre-registered"
created: 2026-09-14
updated: 2026-09-14
type: plan
tags: [agents, research, roadmap]
sources: [plans/control-run-5.md, plans/control-run.md, plans/program-1.md, plans/program-2.md, spec/programs/01-job-queue.md, spec/programs/02-log-analyzer.md, research/concepts/empirical-validation-plan.md, spec/design-v0/08-milestone.md]
status: done
---

# The control run, round 6

The round that can confirm or reject chapter 8's null hypothesis: that an agent does as well in an existing language with Mo's checks bolted on. Rounds 1 to 5 ran the baselines bare; this round bolts the checks on (Go with `go vet`, `staticcheck`, and a contracts library; Python under a `uv init` project with `mypy --strict`, `ruff`, and `pydantic`) and adds a second task, the job queue, whose `never`s and durability are where Mo's checks are meant to earn their keep. Two tasks, three languages, three fresh sessions in parallel, each doing both tasks in order. The thresholds below were written before any session started (14 Sep 2026, the time is in the Result section's first line).

Since round 5: steps 22 to 26 (the derived deadline, the runtime surface, the authority hole, a handle in `state`, `delay:`, the one-line `if` as a value, `state` and `old` as field names) and program 5. The Mo briefs are [[program-2]] and [[program-1]] word for word; the baseline brief is [[control-run]] with the amendments below.

## Setup

| worker | worktree | branch | removed before start |
|---|---|---|---|
| Mo | `../mo-lang-control6-mo` | `control6-mo` | `examples/programs/logstat/`, `examples/programs/logstat.expected` and its `# run:` lines, `examples/programs/jobq/` and its `.expected` files |
| Go | `../mo-lang-control6-go` | `control6-go` | `experiments/control-run/go/` |
| Python | `../mo-lang-control6-python` | `control6-python` | `experiments/control-run/python/` |

Worktrees from `session-05` on the exe.dev VM (Linux x86_64, 4 cores, 15 GB; the earlier rounds ran on Robert's Mac, so wall-clock compares within this round, not to round 5). Agents `mo-r6-mo`, `mo-r6-go`, `mo-r6-python`, each `cd`'d into its worktree before `herdr agent start`. The branches are evidence and are not merged. Tools on the machine before the start: Zig 0.16.0, Go 1.26.5, `staticcheck` 2026.2.1 (`go install`), `uv`, `mypy` 2.3.1 as a `uv` tool at the start (uninstalled during the run on Robert's rule that Python tools live in the project's own environment; the next round adds them with `uv add --dev`) and `ruff` 0.16.1 from Robert's `mise`; `pydantic` in each Python project's own environment. The pane's token count is read before each report.

## The baselines' amendments to the brief

Word for word [[control-run]], with these changes, given to the Go and Python agents in their prompt:

1. Two tasks in order, `logstat` from `spec/programs/02-log-analyzer.md` in `experiments/control-run/<lang>/logstat/`, then `jobq` from `spec/programs/01-job-queue.md` in `experiments/control-run/<lang>/jobq/`; a final message per task with the measurements.
2. The checks are required, not "if available": Go runs `go vet` and `staticcheck` clean and uses a contracts library (one from `pkg.go.dev` of the agent's choosing, or a `contract` package of its own of at most 40 lines with `Require`, `Ensure`, and `Invariant` that fail with the condition's text, the choice said in the report); Python is a `uv init` project, `mypy --strict` and `ruff check` clean, `pydantic` models for every JSON shape and every validated input. The standard-library rule bends only for these: the contracts library and `pydantic`.
3. Reading the `jobq` spec outside Mo: a `never` is an assertion checked on every state change plus a test that tries to break it; an `invariant` is a check after every operation on the queue; `requires`/`ensures` are the contracts library's calls with a test each; `within:` is a timeout on every call that can wait; `--sim 100 --faults` is a test that runs the queue under 100 seeds of injected file and socket failures with the durability rules checked after each; the store recipe is any append-only log that replays; the 1,200 idle connections test stands as written. The `within:` count is reported as the count of timeout literals, chosen or derived.
4. Measured, per task, in the final message: loops to green by cause (a check the language or a tool made, a test mistake, a real bug, tooling), wall-clock, functions with median and max lines, program plus test lines, which checks caught a real bug the agent's own tests did not, and every point where the language or a library forced a decision the spec did not make.

## Pre-registered

Four predictions. All four must hold for the round to count as "held"; any one failing makes it "mixed", and the reading says which. The null hypothesis is stated by P3: if it fails in the baselines' favour, the hypothesis stands and the page says so plainly.

| prediction | threshold | the last number |
|---|---|---|
| P1, wall-clock | Mo at most 1.5 times Go, summed over both tasks | 1.28 on logstat (round 5); jobq has no baseline |
| P2, loops by cause | Mo has no loop from a shape law and at most one from a grammar form or a misleading diagnostic across both tasks; test-mistake loops count against no language | round 5: 0 law, 1 form; round 4: 0 law, 4 form |
| P3, the checks (the null hypothesis) | on `jobq`, Mo's bolted-in checks (`never`, `invariant`, a contract, `--sim`) catch at least one real bug the worker's own tests did not, and the baselines' bolted-on checks (vet, staticcheck, the contracts library; mypy, ruff, pydantic) catch no more real bugs than Mo's; a type error the language would have refused anyway does not count | program 1: two `never`s tripped under `--sim` during the build; rounds 1–5: no baseline check caught a bug in code |
| P4, size | Mo's program plus test lines at most 0.65 of Go's on `jobq` | logstat: 831 to 1,552 (0.54) |

Recorded for every worker besides: whether it wrote the language directly, the pane's token count at the end of each task, the `within:` (timeout) count with its chosen and derived columns, and the Q16 ledger for Mo (a law that blocked the program).

## Result

The sessions started 14 Sep 2026, 14:30 UTC (the page and its predictions were committed at 14:27, `16b4b05`). Removed from the Mo worktree besides the folders: the two programs' rows in `examples/README.md` and their entries in `programs/.mo.ids`, so the README does not describe the shapes. Go finished at 15:04, Python at 15:11, Mo at 15:23; no sleep, timing valid. Scored by Fable from the three final reports (saved from the panes and the transcripts) and its own verification in each worktree: Mo `zig build test` 185 of 185 with both programs in the corpus (every `# run:` line under `mo run` and as a binary), `mo fmt --check` clean, logstat and `jobq check` run by hand; Go `go vet`, `staticcheck`, `go test`, and `check.sh` clean for both tasks; Python `mypy --strict`, `ruff check`, 70 and 106 `unittest` tests, and `check.sh` clean for both.

| | Mo | Go, checks bolted on | Python, checks bolted on |
|---|---|---|---|
| wall-clock, logstat | 16.4 min | 7.4 | 9.5 |
| wall-clock, jobq | 34.6 min | 25 | 28.6 |
| wall-clock, both, from the prompt | **51.0 min** | 32.2 | 39.0 |
| loops to green, logstat, by cause | 4: 2 language checks (a `never` over `Summary.all` tripped on a `var` copy between two field assignments, a false trip; `MO0101` for an assignment on a `case` arm's line), 1 test mistake, 1 tooling (the README's run-folder sentence) | 0 | 2, both tool noise (mypy outside the venv, ruff line length) |
| loops to green, jobq, by cause | 6: 5 language checks (`state` as a parameter, then as a binding; `result` as a parameter with the bare "expected a name"; the 500-line file law `MO0302` splitting `board.mo`; `Time.fixture()` in a helper, `MO0403`), 1 tooling (`"\u0085"` read as five letters with no diagnostic) | 2 (a missing import the compiler found; a test mistake) plus 3 tooling (escapes written raw, a wrong directory) | 5: 4 tool noise (mypy inference, ruff style), 1 test mistake |
| functions, jobq: count, median, max lines | 170, 4, 20 | 103 program + 90 test, 8 / 14.5, 41 / 106 | 152 program + 149 test, 5 / 6, 39 / 44 |
| program + test lines, logstat | 793 | 1,292 | 1,083 |
| program + test lines, jobq | 2,650 (1,952 + 698) | 3,578 (1,604 + 1,974) | 3,390 (1,734 + 1,656) |
| checks that caught a real bug the worker's tests did not | **none** in either task; the `never` trip was a half-built value, not a wrong result | none beyond the compiler's missing import; the contracts fired only in the tests written to fire them; 5 deliberate bugs planted afterwards were all caught by the sim and unit tests | none; mypy and ruff found typing and style only |
| contracts library | the language's | its own 28-line `contract` package (Go cannot capture an expression's text, so every condition is written twice) | its own 15-line `contract.py` plus pydantic models |
| `within:` count, jobq | 44 literals, 43 chosen, 1 derived by hand; none on `reply_by`, since the copied store recipe takes no deadline; one literal lies (a call can wait about 90 s in the store against a 60 s ask) | 6 chosen timeouts, 6 derived without a literal; fsync has no deadline | 6 literals, 5 chosen, 8 derived waits, 4 unbounded; fsync has no deadline |
| lease+ack pairs a second, 1 / 32 workers | 307 / 399 native, 308 / 332 interpreted | 743 / 858 | 342 / 377 |
| lag from a lease running out to handed out again | 4.8 ms median native, 5.0 interpreted | 2.6 ms median | 1.9 ms median |
| resident memory at 100k jobs | 192 MiB native, 404 interpreted | 73 MiB | 191 MiB |
| replay of a 1M-record log | 14.2 s native, 56.9 interpreted | 7.3 s | 9.5 s |
| restart with 10,000 run-out leases | 0.16 s to serve, then 45 s to lease them all again (quadratic: each lease walks past the jobs just leased) | 79 ms, then 8.0 s | 0.23 s, then 0.19 s |
| the 1,200 quiet connections | held with `mailbox: 4_096`; at the default bound only 1,199 opened and the producer waited on `idle` | held; a goroutine a connection, no acceptor bound | held; the limit is descriptors, 4,096 here |
| invariants kept | 0 of 8 candidates, each refused before a message can break it | 6 checked on every change and on replay, each tripped by a hand-written log line; 3 left out | 7, each tripped by a hand-made record; 4 left out |
| stdlib gaps, toolchain bugs | 2 gaps (`fold_lines` loses the fold at `NotText`; no code-point escape in a string), 3 bug notes (the `never` over a `var` copy; the silent `\u` escape; `result`'s bare diagnostic) | 0, 0 | 0, 0 (the pydantic mypy plugin cannot run from a mypy outside the venv) |
| wrote the language directly | yes | yes | yes |
| output tokens, from the transcript's summed usage | 1.01 M over 329 turns | 1.21 M over 141 | 1.26 M over 134 |
| verified by Fable | yes | yes | yes |

Three things about the comparison itself. The Go and Python worktrees still held `examples/programs/logstat/` (only the Mo worktree had it removed), and both copied its fixture, as rounds 1 to 5 did; the Mo worker wrote its own fixture. The baselines' contracts libraries were their own, since none fit from `pkg.go.dev` in the agent's judgment. The Python worker ran the machine's `mypy` against its venv's Python; Robert's rule that Python tools live in the project's own environment came during the run and holds from the next round.

## Reading, against the predictions

| prediction | threshold | round 6 | held |
|---|---|---|---|
| P1, wall-clock | Mo at most 1.5 times Go, both tasks | 1.58 (51.0 to 32.2); logstat alone 2.2, jobq alone 1.4 | **no** |
| P2, loops by cause | no shape-law loop, at most one grammar-form or misleading-diagnostic loop | one shape-law loop (`MO0302`, the 500-line file, splitting `board.mo`); two form or diagnostic loops (the `case` arm assignment; `result`'s bare message); plus three keyword-collision loops (`state` twice, `result`) | **no** |
| P3, the checks (the null hypothesis) | Mo's checks catch at least one real bug the tests did not, and the baselines' checks catch no more | Mo's checks caught none in either task; the baselines' caught none either (Go's compiler found an import) | **no**, and the null hypothesis stands |
| P4, size | Mo at most 0.65 of Go's lines on jobq | 0.74; program lines alone 1,952 to Go's 1,604, Mo longer | **no** |

**Failed, all four.** This is the first round to fail outright, and the one that was built to answer chapter 8's question. The honest reading, in order of weight:

1. **The null hypothesis stands.** With the same checks bolted onto Go and Python (contracts as explicit calls with a test each, an invariant checked on every change, a `never` as an assertion plus a test that tries to break it, a 100-seed fault simulation), all three workers shipped a correct job queue by their own tests, and no bolted-in or bolted-on check caught a real bug in any of the three. Mo's checks did not earn their cost on this task; neither did the baselines', but theirs cost less. Program 1's two `never` trips during its build remain the only time a Mo check has caught a real bug in a real program, and they were the worker's own during the build, not after.
2. **Mo's loops are the language's, the baselines' are the tools'.** Mo's ten loops: five keyword or grammar refusals (`state`, `state`, `result`, a `case` arm assignment, a fixture in a helper), one shape law (the 500-line file), one false `never` trip, one test mistake, two tooling. Go's five and Python's seven were almost all tool noise (escapes, line length, mypy inference), plus one test mistake each. Keywords that are common English nouns (`state`, `result`, `old`) cost three loops in one program; step 25's ruling that `state` may name a field did not reach parameters and bindings.
3. **The interpreter is not a runtime for this program.** Under `mo run`, jobq holds 404 MiB at 100k jobs, replays 1M records in 57 s, and re-leases 10,000 jobs in 158 s; native is 192 MiB, 14 s, 45 s; Go is 73 MiB, 7.3 s, 8 s. The re-lease is quadratic in the program, not the runtime, but Go's and Python's workers avoided it with a heap and Mo's did not.
4. **The `never` over `T.all` forbids the language's own idiom.** Chapter 4's way to change a struct is a `var` copy set field by field; a `never` relating two fields reads the copy between the assignments. Either the rule or the idiom has to give; a bug note with a 20-line reproduction is in `logstat/TOOLCHAIN-BUGS.md`.
5. **Size held on logstat and not on jobq.** Mo's jobq program is longer than Go's; its tests are a third of Go's. The 70-line function law holds (max 20) and the 500-line file law cost a split.

**What changes.** Robert agreed to all three the same afternoon (locked rows of 14 Sep; [[interpreter-step-27]] builds them; the file law is dropped rather than demoted, since the honesty laws forbid warnings). These were Robert's calls, recorded as rows for him with Fable's recommendation on each: (a) the laws are re-evaluated against six rounds and two real programs, since this round shows a shape law costing a loop and no check earning one; Fable recommends keeping the function law, dropping the 500-line file law to a warning, and making `state`, `result`, and `old` names everywhere but the positions the grammar reserves, as step 25 began; (b) the `never` over `T.all` and the `var` copy idiom, a semantic row; (c) a `\u` escape or a diagnostic for an unknown escape, and `result`'s message, one small step; (d) the next round is not run until one of these lands, since a seventh round of the same design would measure the same thing. The founding premise is not refuted by one round with one model, but chapter 8's own test was run as designed and Mo did not pass it.

## Related
- [[control-run-5]]
- [[control-run]]
- [[program-1]]
- [[program-2]]
- [[empirical-validation-plan]]
- [[roadmap]]
