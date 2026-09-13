---
title: "Program 2: logstat in Mo, brief for the worker"
created: 2026-09-12
updated: 2026-09-12
type: plan
tags: [agents, roadmap, stdlib]
sources: [spec/programs/02-log-analyzer.md, plans/program-menu.md]
status: proposed
---

# Program 2: `logstat` in Mo, brief for the worker

The first real program. The spec is `mo-wiki/spec/programs/02-log-analyzer.md`; implement it in Mo, in `examples/programs/logstat/`, using only what the toolchain provides today. This is an experiment about the language, so how you work is part of the result: record everything the spec's last section asks for.

## Orientation

`mo-wiki/spec/programs/02-log-analyzer.md` (the spec, read twice), `mo-wiki/spec/design-v0/04-syntax.md`, `toolchain/PRELUDE.md` (everything that exists), `toolchain/FORMAT.md`, `examples/programs/` (how a program with `main` and a `.expected` file is laid out), and any corpus file you need as a pattern.

## Write scope

`examples/` only. If the toolchain has a bug, do not fix it: record it in `examples/programs/logstat/TOOLCHAIN-BUGS.md` with a minimal reproduction and work around it. If the language or stdlib lacks something, do not invent syntax: record it in `examples/GAPS.md` and find the plainest way inside what exists. Branch `session-05`; commit after each module.

## Shape

Modules under `examples/programs/logstat/`: `Logstat.Parse` (line to record), `Logstat.Stats` (records to summary), `Logstat.Report` (summary to text and JSON), `Logstat.Main` (`main`, arguments, files). Each module has its `expose` line, `intent`, contracts, and tests at the bottom. `main` follows Q18: the `case` at its foot is the error policy. Every `requires` has its `rejects`. Formatted with `mo fmt`.

## Fixture and program check

`examples/programs/logstat/fixture/` with three `.log` files (one with malformed lines and a card number in a path), and `examples/programs/logstat.mo`? No: the program is the `Logstat.Main` module; add the `# run:` line and `logstat.expected` beside it so the corpus test runs it as it runs the other programs. If the corpus test cannot run a multi-module program, record that as the first toolchain bug and give the program-level check as a shell line in the README.

## Done when

`mo test` passes on every module, `mo run` on the fixture matches the expected output for the text and the JSON form, `mo fmt --check` is clean, everything is pushed, and the final message contains the measurements the spec asks for plus every decision the spec left open.

## Related
- [[program-menu]]
- [[q18-main-and-the-platform]]
- [[interpreter-step-6]]
- [[roadmap]]
