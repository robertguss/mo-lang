---
title: "The control run: logstat in Go and Python, brief for the worker"
created: 2026-09-12
updated: 2026-09-12
type: plan
tags: [agents, research, roadmap]
sources: [spec/programs/02-log-analyzer.md, spec/design-v0/08-milestone.md]
status: done
---

# The control run: `logstat` in Go and Python, brief for the worker

Chapter 8's null hypothesis: agents might do as well in an existing language with Mo's checks bolted on. The first number: the same worker model implements the same spec, `mo-wiki/spec/programs/02-log-analyzer.md`, in Go and in Python, with the same measurements recorded. One fresh session per language, so neither sees the Mo implementation or the other.

## Write scope

`experiments/control-run/go/` or `experiments/control-run/python/` only (the brief names one). Branch `session-05`. Commit after each file.

## The rules, to make it fair

- Same spec, read twice, no other design help. Every open point in the spec is decided by you and listed in the final message.
- Bolt on Mo's checks as far as the language allows: Go with `go vet` and `staticcheck` if available, exhaustive error handling, no panics on input; Python 3 with type hints checked by `mypy --strict` if available, no bare `except`. Contracts as explicit checks that raise or return errors; a test for every one. Tests for every output section, a property-style test over generated records (`errors <= requests`), and a fixture directory of three log files with malformed lines and a card number in a path, identical in content to `examples/programs/logstat/fixture/` if it exists, otherwise create it and say so.
- Standard library only. No third-party packages.
- The program-level check: a script `check.sh` that runs the program over the fixture and diffs against `expected.txt` and `expected.json`.

## Measured (in the final message)

Loops to green (how many test or check runs failed before the last one passed), wall-clock time, lines per function (max and median), total lines, which checks caught real bugs and which were noise, and every point where the language or stdlib forced a decision the spec did not make.

## Done when

`check.sh` passes, tests pass, type checks and vets pass, pushed, measurements in the final message.

## Result, round 1 (13 Sep 2026, 00:18 to 00:45)

Same spec, same model (Opus), three fresh sessions in parallel. Scored by Fable from the three final reports and its own verification.

| | Mo | Go | Python |
|---|---|---|---|
| wall-clock | 25.5 min | 12.9 min | 8 min |
| loops to green (code) | 2 | 0 | 1 |
| loops to green (tooling) | 2 (file limit) + 4 probes | 2 (staticcheck) | 0 |
| functions | 78 | 54 | 37 |
| lines per function, median / max | 4.5 / 21 | 8 / 28 | 6 / 24 |
| program + test lines | 1,174 | 1,533 | 993 |
| checks that caught a real bug | 2 (`MO0222`, `MO0201`) | 0 | 0 (2 test mistakes) |
| stdlib or platform gaps hit | 9 | 2 | 6 |
| verified end to end by Fable | yes, with the file limit lifted | yes | yes |

**Honest reading.** Mo lost on time, two to three times slower, and every minute of the loss is toolchain: no multi-module programs, no sort, no map, no split, no directory listing, no number parsing, and an interpreter at 3.7 ms per log line. None of it is the language design. Mo won on shape: shortest functions by a wide margin (the 70-line law was never near), the only run where a diagnostic caught a bug in the code, and the only run whose contracts are checked by the toolchain rather than hand-written asserts. Go's and Python's checks caught nothing; their workers reported that as noise. The control run cannot yet say whether Mo's checks pay off, because no run had a bug that mattered; it does say the cost of Mo today is the stdlib and the runtime, and nothing else. First tested again after step 8, same spec, same three languages.

## Related
- [[program-2]]
- [[program-menu]]
- [[roadmap]]
