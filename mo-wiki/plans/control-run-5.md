---
title: "The control run, round 5: logstat after step 21 and program 1, pre-registered"
created: 2026-09-14
updated: 2026-09-14
type: plan
tags: [agents, research, roadmap]
sources: [plans/control-run-4.md, research/concepts/empirical-validation-plan.md, plans/program-2.md, plans/control-run.md, deep-dives/research-agenda-2026-09-response.md]
status: done
---

# The control run, round 5

The first pre-registered round, as [[empirical-validation-plan]] asked: the thresholds below were written before any session started (14 Sep 2026, 01:12; the sessions started 01:14). Same spec, same model, three fresh sessions in parallel in worktrees from which the earlier implementations are removed, briefs word for word [[program-2]] and [[control-run]], so the round compares with round 4, the timing round. The toolchain since round 4: step 21 (green threads, three diagnostics for round 4's loops, `mo fix` for the one-line `if`) and program 1's evidence. Nothing in the briefs changed; the bolted-on-checks arm for the baselines (Go with a contracts library, Python with `pydantic`) waits for a round with a second task, since changing the baselines' briefs would break the comparison this round exists for.

## Setup

| worker | worktree | branch | removed before start |
|---|---|---|---|
| Mo | `../mo-lang-control5-mo` | `control5-mo` | `examples/programs/logstat/` |
| Go | `../mo-lang-control5-go` | `control5-go` | `experiments/control-run/go/` |
| Python | `../mo-lang-control5-python` | `control5-python` | `experiments/control-run/python/` |

Agents `mo-r5-mo`, `mo-r5-go`, `mo-r5-python`. The branches are evidence and are not merged.

## Pre-registered

Three predictions, decided before the run; all three must hold for the round to count as "held", any one failing makes it "mixed", and the reading says which.

| prediction | threshold | round 4 |
|---|---|---|
| P1, wall-clock | Mo at most 1.5 times Go | 1.73 |
| P2, loops to green | Mo at most Go's plus 2 | 5 to 1 |
| P3, the laws | no loop from a shape law, and none from the three forms step 21 gave diagnostics for | 0 law loops, 3 form loops |

Two new columns, recorded for every worker: loops by cause (a law, a grammar form, a diagnostic, a test mistake, a real bug) and whether the worker wrote its language directly or wrote a generator for it (from the pane and the commits). Tokens: the pane's final status line per session (Claude Code's own count), amortized preamble not separated this round.

## Result (14 Sep 2026, 01:14 to 01:31; no sleep, timing valid)

| | Mo round 4 | **Mo round 5** | Go round 5 | Python round 5 |
|---|---|---|---|---|
| wall-clock to the last commit | 16.1 min | **14.8** (17.1 to done, with the corpus test) | 11.6 | 14.9 |
| loops to green | 5 | **5**: 3 test mistakes, 1 grammar form (`is` inside `==` needs parentheses, `MO0101`), 1 law (`assert` and a fixture in a shared helper, `MO0214` and `MO0403`) | 2 (an unused import and gofmt with a broken staticcheck; a layout bug and a test mistake) | 3 (1 code: a test mistake beside a real bug; 2 tooling, ruff's flags) |
| functions | 61, median 3, max 17 | **67, median 3, max 14** | 47, median 10, max 37 | 51, median 4, max 15 |
| program + test lines | 849 | **831** | 1,552 | 1,334 |
| checks that caught a real bug | 0 | **0** | 1 (a test: a layout rule) | 1 (a test: a leaked descriptor) |
| stdlib gaps, toolchain bugs | 1, 1 | **3, 0** (`fold_lines` fails a file at its first non-UTF-8 line; `Fs.list` does not tell files from folders; no thousands separator) | 0, 1 (the installed staticcheck cannot read Go 1.27) | 0, 1 (mypy not installed, so no type check in any round) |
| wrote the language directly | — | **yes** | yes | yes |
| verified by Fable | yes | **yes**: `zig build test` green in the worktree, `mo fmt --check` clean, five run lines | yes: `check.sh`, `go test`, `go vet` | yes: `check.sh`, `unittest` |

After the fact (14 Sep, morning, once mypy was installed as a `uv` tool): the round 5 Python passes `mypy --strict` with no issues in its 9 files, so its unchecked type hints were sound; the row above stands as the round ran. Tokens: not captured; the panes' status lines had scrolled off by the end (Mo showed 54k output tokens at 13 minutes, Python 72k). The next round reads them before the report.

## Reading, against the predictions

| prediction | threshold | round 5 | held |
|---|---|---|---|
| P1, wall-clock | Mo at most 1.5 times Go | 1.28 to the last commit, 1.47 to done | yes |
| P2, loops to green | Mo at most Go's plus 2 | 5 to 2 | **no**, by one |
| P3, the laws | no loop from a shape law or the three step 21 forms | none from either | yes |

**Mixed.** Two of three held. Mo's wall-clock ratio fell from 1.73 to 1.28, the best of any round, on the timing round's own terms; Go's time rose to 11.6 (a broken staticcheck cost it a rebuild). Mo's five loops are the same count as round 4 but a different shape: three were the worker's own test mistakes (a star count, an argument order, a padding width), which Go and Python had one and one of; one was a grammar form the three step 21 diagnostics did not cover (`is` inside a comparison), and one was the honesty laws doing their job (`assert` outside a test, a fixture outside a test), which the worker fixed in one pass and named as a diagnostic that helped. No shape law tripped for the fourth round running. The three forms step 21 gave diagnostics for did not recur. No check caught a real bug in Mo this round; Go's and Python's tests each caught one, and in both cases the bug was in code Mo's shape would have written the same way (a padding rule, a descriptor leak the platform owns). Mo's program is half Go's size and its functions a third the length, as before.

**What changes.** The laws stay; four rounds without a shape-law loop is the evidence Robert asked for on 13 Sep. The next ergonomics item is the `is` form inside a comparison, one diagnostic, to step 22. P2 was set on round 4's ratio and missed by one loop on a count of five; the next round pre-registers loops by cause rather than a total, since test mistakes are the worker's, not the language's. Tokens are read before the report. The baselines' bolted-on arm still waits for a second task.

## Related
- [[interpreter-step-21]]
- [[control-run-6]]
- [[control-run-4]]
- [[empirical-validation-plan]]
- [[program-2]]
- [[control-run]]
- [[roadmap]]
