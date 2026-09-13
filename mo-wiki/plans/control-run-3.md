---
title: "The control run, round 3: logstat after the formatter fixes and HTTP"
created: 2026-09-13
updated: 2026-09-13
type: plan
tags: [agents, research, roadmap]
sources: [plans/control-run-2.md, plans/control-run.md, spec/programs/02-log-analyzer.md]
status: done
---

# The control run, round 3

Round 2 (13 Sep, 09:25) put Mo at 11.8 minutes against Go's 8.2 and Python's 7.9, with the rest of the gap traced to `mo fmt`'s line breaking and five stdlib rows. Step 14 fixed all of it. Round 3 reruns the identical experiment on the toolchain after steps 14 to 16: same spec, same model, three fresh sessions in parallel, in worktrees from which the round 2 implementations have been deleted so nothing is copied.

## Setup

| worker | worktree | branch | removed before start |
|---|---|---|---|
| Mo | `../mo-lang-control3-mo` | `control3-mo` | `examples/programs/logstat/` |
| Go | `../mo-lang-control3-go` | `control3-go` | `experiments/control-run/go/` |
| Python | `../mo-lang-control3-python` | `control3-python` | `experiments/control-run/python/` |

Briefs are word for word [[program-2]] and [[control-run]]; the Mo worker writes to `examples/programs/logstat/` as before. Agents `mo-r3-mo`, `mo-r3-go`, `mo-r3-python`. The branches are evidence and are not merged; the numbers and the Mo program's gaps are what round 3 produces.

## Result (13 Sep 2026, 13:58 to 14:21)

| | Mo round 2 | **Mo round 3** | Go round 3 | Python round 3 |
|---|---|---|---|---|
| wall-clock | 11.8 min | **23.4 min**, void: the machine slept mid-run; includes the toolchain build and the corpus test | 18.3 min, void: the same sleep | 7.3 min, done before the sleep |
| loops to green (code) | 0 | **3** (one real bug, two test mistakes) | 0 | 1 (own test wrong) |
| loops to green (tooling) | 0 | **6** (five syntax or law diagnostics, one stale `verified:` line) | 2 (staticcheck version, a shell cwd) | 0 |
| functions | 4 modules, median 3, max 12 | 56, median **6** (bodies 4), max 19 | 44, median 9.5, max 36 | 39, median 5, max 24 |
| program + test lines | 791 | **851** | 1,387 | 1,064 |
| checks that caught a real bug | 0 | **2**: a test (busiest counts off by one) and a `never` (a half-built summary) | 0 | 0 |
| stdlib gaps hit | 5 | 1 (`Fs.each_line` cannot fold), plus 2 toolchain bugs | 0 | 0 |
| verified by Fable | yes, as is | **yes, as is**: four modules green, five runs against their expected files, `mo fmt --check` clean, the corpus test green in the worktree | yes: `check.sh`, `go test`, `go vet` | yes: `check.sh`, 69 tests (mypy not on Fable's machine; the worker reports it clean) |

**Reading.** The wall-clock column is unusable for Mo and Go this round: Robert's machine slept while both were running (the Mo pane shows the API error), and Mo's time also holds a toolchain build and a full corpus run. The other columns stand. Mo's loops went from zero to nine, and six of them are the toolchain refusing the model's first guess at Mo syntax or a law: `assert` as a `case` arm, a one-field variant matched by name, a line wrapped inside a string, an assignment on a one-line arm, a `_` arm on a closed type, a `verified:` line edited after `--write`. Each cost one run and was fixed on sight, and none was a behaviour bug, but the worker singled out `MO0101`'s wording as unhelpful; that is the cheapest thing to fix. For the first time a control run had a real bug for the checks to catch, and Mo's caught it twice over: a test found the off-by-one and a `never` found the invariant break on a half-built value, which the worker then designed away. Go's and Python's caught nothing, having nothing to catch. Two toolchain bugs surfaced: `any(T)` ignores a refinement's `where` (a property test generated a `Percent` of 65,535), which is a soundness bug in the property runner, and `Fs.read_lines` hands back a `String` that is not UTF-8. Both go to step 17 before program 4 builds on the same rows. Mo's functions are still the shortest, and its program is 60 percent of Go's length.

## Related
- [[control-run-2]]
- [[control-run]]
- [[program-2]]
- [[roadmap]]
