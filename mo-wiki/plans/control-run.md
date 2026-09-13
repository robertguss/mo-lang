---
title: "The control run: logstat in Go and Python, brief for the worker"
created: 2026-09-12
updated: 2026-09-12
type: plan
tags: [agents, research, roadmap]
sources: [spec/programs/02-log-analyzer.md, spec/design-v0/08-milestone.md]
status: proposed
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

## Related
- [[program-2]]
- [[program-menu]]
- [[roadmap]]
