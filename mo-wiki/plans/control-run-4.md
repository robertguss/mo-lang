---
title: "The control run, round 4: logstat after steps 17–20, the timing round"
created: 2026-09-13
updated: 2026-09-13
type: plan
tags: [agents, research, roadmap]
sources: [plans/control-run-3.md, plans/control-run.md, spec/programs/02-log-analyzer.md, deep-dives/outside-review-2026-09-13-response.md]
status: done
---

# The control run, round 4

Round 3 (13 Sep, 13:58) lost its wall-clock column to the machine sleeping, and put Mo at 9 loops to green against Go's 2 and Python's 1, six of Mo's loops syntax diagnostics. Steps 17 to 20 reworded those diagnostics, fixed the two toolchain bugs the run found, and changed how servers are written. Round 4 reruns the identical experiment: same spec, same model, three fresh sessions in parallel, in worktrees from which the earlier implementations have been deleted. It is the round the laws are re-evaluated against ([[outside-review-2026-09-13-response]]).

## Setup

| worker | worktree | branch | removed before start |
|---|---|---|---|
| Mo | `../mo-lang-control4-mo` | `control4-mo` | `examples/programs/logstat/` |
| Go | `../mo-lang-control4-go` | `control4-go` | `experiments/control-run/go/` |
| Python | `../mo-lang-control4-python` | `control4-python` | `experiments/control-run/python/` |

Briefs are word for word [[program-2]] and [[control-run]]; agents `mo-r4-mo`, `mo-r4-go`, `mo-r4-python`. The branches are evidence and are not merged.

## Result (13 Sep 2026, 21:07 to 21:23; no sleep, timing valid)

| | Mo round 2 | Mo round 3 | **Mo round 4** | Go round 4 | Python round 4 |
|---|---|---|---|---|---|
| wall-clock | 11.8 min | void | **16.1 min** | 9.3 min | 9.0 min |
| loops to green (code) | 0 | 3 | **1** (a test's wrong expectation) | 0 | 0 |
| loops to green (tooling) | 0 | 6 | **4**: `MO0206` (a misleading one: `0..60.map` binding to 60), `MO0101` twice (a one-line `if` expression; a two-field variant pattern without names), `MO0309` (a `_` arm, with the exact fix) | 1 (staticcheck's version) | 0 |
| functions | median 3, max 12 | 56, median 6, max 19 | **61, median 3, max 17** | 63, median 9, max 25 | median 5 |
| program + test lines | 791 | 851 | **849** | 1,648 | 1,095 |
| checks that caught a real bug | 0 | 2 | **0** | 0 | 0 |
| stdlib gaps, toolchain bugs | 5, 0 | 1, 2 | **1, 1** (`Fs.fixture()` does not refuse `..` as the real `Fs` does) | 0 | 0 |
| verified by Fable | yes | yes | **yes, as is**: four modules green, five run lines, `mo fmt --check` clean, the corpus test green in the worktree | yes: `check.sh`, `go test`, `go vet` | yes: `check.sh`, `unittest` |

**Reading.** With the timing valid again, Mo is about 1.75 times Go and Python on wall-clock, worse than round 2's 1.45 and on a toolchain that has grown since. Loops fell from nine to five, and every one of the four tooling loops is the model's first guess at a shape the grammar does not have: a one-line `if` as an expression, a two-field variant matched by position, a range method call binding to the last integer, a `_` arm. None is a law. The reworded diagnostics did their job (the `MO0309` fix was applied verbatim), and `MO0101` recurred twice, as it did for Fable writing probes the same evening; that pattern, statements and expressions on one-line arms, is the single most expensive habit in the language for a model, and it is a grammar ergonomics question, not a shape law. No check caught a behaviour bug in any language this round, and there was none to catch; round 3 remains the only round with a bug, and Mo caught it. Mo's functions are a third the length of Go's, the program half the size. The fictional-bound count is not exercised by a CLI, and after step 20 it is zero in every server.

**The laws, re-evaluated against [[outside-review-2026-09-13-response]].** Across rounds 2 to 4 no loop was caused by a shape law: no run tripped the 70-line, 500-line, six-parameter, or nesting limits. The no-`while` law cost fictional bounds in every server until step 20 removed the need for them without a keyword. The `test rejects` per `requires` law cost no loops. The laws are not where Mo's time goes; the grammar's one-line forms and a misleading type error are. Fable's recommendation: keep every law as it is; spend the next ergonomics step on the grammar's one-line arm and `if` forms and on `MO0206`'s wording when a method binds to a literal; rerun after program 1 as round 5.

## Related
- [[control-run-3]]
- [[control-run]]
- [[program-2]]
- [[roadmap]]
