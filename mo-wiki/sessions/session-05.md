---
title: "Session 5 — 12–13 Sep 2026"
created: 2026-09-12
updated: 2026-09-13
type: session
tags: [meta, compiler, syntax, agents, runtime]
sources: [spec/grammar.md, plans/corpus.md, plans/model-bakeoff.md, plans/control-run-2.md, decisions/decision-log.md]
date: 2026-09-12
session: 5
---

# Session 5 — 12–13 Sep 2026

The longest session so far, about twenty hours across an evening, an overnight run with Robert asleep, and a morning. The design review closed; Mo went from prose to a toolchain that checks, tests, simulates, formats, fixes, runs, and compiles programs; three real programs were written from specs; the founding premise got its first two numbers. The process changed twice: build first and decide as we go, then Fable decides and documents while Opus builds everything.

## Evening (12 Sep)

- Robert reviewed design-v0 chapters 1–3 and 5–8 with no edits.
- [[corpus]]: Opus wrote the 50-file corpus in eight minutes. [[model-bakeoff]]: Grok and Codex ran the identical brief; Opus won on taste and gap discipline, Codex found three grammar bugs, Grok filled files with tautologies. Fable chose Opus as the worker for all code.
- `toolchain/` laid out in Zig 0.16 with the benchmark harness first. Robert: feature branches, no taste review of the corpus, build and measure, keep a decision log and a changelog → [[decision-log]], `CHANGELOG.md`.
- Fable decided every gap the corpora found (grammar Session 5 decisions). Steps 1–4: lexer, parser, tier-1 checker, VM, tier-2 contracts, test runner, processes, supervisors, `Mo.Sim` scheduler. **The chapter 8 milestone was met** at 22:50. The compiler corrected chapter 4's example five times.
- Robert: every phase in a fresh worker session; Fable takes over for the night, merges to `main` per accepted step, whatever it takes.

## Overnight (13 Sep, 00:00–06:30)

- Step 5 formatter; step 6 `main` and `Mo.Server`; program 2 `logstat` from a spec in 25.5 min; the control run in Go (12.9) and Python (8) → [[control-run]]; step 7 multi-module programs, in-place `push`, a region allocator, 100× interpreter speed; step 8 the stdlib (`09-stdlib.md`, 118 rows); step 9 `Mo.Sim` seeds and faults; step 10 sidecar, `mo fix`, error catalog, README; step 11 `Net` and processes under `mo run`.
- A runaway `mo run` at 21 GB was killed and became the quadratic-`push` finding. Memory pressure killed the background waits; the run continued on a timed wakeup.

## Morning (13 Sep, 06:30–11:00)

- Program 3 `kv` over TCP in 40 min: 15k GETs/s, but six runtime bugs and no file writes → [[interpreter-step-12]] fixed all of it (kv durable, 19 MB after 50k SETs). Robert, awake: Fable's recommendations are the decisions; documented; no mistakes at this stage.
- [[interpreter-step-12b]] undid two ratified defaults Fable had flagged: memoization left the reference interpreter, every `never` runs on every test.
- [[interpreter-step-13]]: the C backend, differential-tested, zero differences; native logstat 7× the interpreter. A contracts-off default overturned on acceptance.
- [[control-run-2]]: Mo 11.8 min (from 25.5), zero loops to green, median 3 lines per function; Go 8.2, Python 7.9.
- [[interpreter-step-14]]: contracts in every build, the formatter's round-2 shapes, four stdlib rows.

## Afternoon (13 Sep, from 11:30, a fresh Fable context)

- [[interpreter-step-15]]: processes and `Net` in the C runtime; `mo build` compiles everything; native kv 1.4× the interpreter at half the memory. [[interpreter-step-16]]: `Http` over `Net` in both runtimes, `httpd`; native 1.7× the interpreter. [[control-run-3]]: Mo 9 loops (6 syntax diagnostics), a real bug caught by a test and a `never`, timing void (the machine slept). [[interpreter-step-17]]: the round 3 follow-ups. The [[outside-review-2026-09-13|outside review]] arrived on `main`; Fable's [[outside-review-2026-09-13-response|response]]; Robert: laws stay, test and re-evaluate. [[interpreter-step-18]]: the review's no-compat fixes, all five, both runtimes; Fable wrote the failure model into chapter 3. [[program-4]]: `notes` in 55 minutes, the first program over HTTP and from two recipes; native 23,692 gets/s; a started process is never freed and a held send can deadlock, both to [[interpreter-step-19]], which fixed them (200,000 processes at 9 MB native) and added recipe conformance, `mkdir`, a fixed clock, and mutation tests. Robert chose the runtime owning the loop over a `loop` keyword after Fable unpacked three answers to the fictional-bound loops; [[interpreter-step-20]]: the runtime owns the loop, 11 fictional bounds to 0, every expected file unchanged. [[control-run-4]]: timing valid, Mo 16.1 min to Go's 9.3 and Python's 9.0, loops 5/1/0, the laws kept with an ergonomics step recommended for Robert. The outside review page's suggested-prompt lines in the worker pane were Claude Code's, not Robert's; the record was corrected.

## Night (13 Sep, from 22:00, a fresh Fable context)

- [[research-agenda-2026-09-response]]: the research agenda's twelve concept pages read; seventeen contradictions called (agree 8, disagree 6, test 3). Chapter 2's recursion law now matches the toolchain (a depth bound, termination for `mo prove`); chapter 3 names Armstrong's R6; the Q16 ledger, the nine-nines rule, reproducible builds as a release gate; round 5 counts loops by cause and whether the worker wrote Mo; program 1 counts its deadlines. Measured: `mo build` byte-identical across two `mo` binaries; `mo` differs only in the Mach-O UUID and its signature.

## Numbers at the end of the session

| what | number |
|---|---|
| corpus files | 75 (plus kv, echo, logstat programs) |
| toolchain, Zig | about 30k lines |
| diagnostics with a catalog entry | 60 |
| whole corpus lex+parse+check | about 2 ms |
| logstat 200k lines: interpreter / native | 0.95 s / 0.14 s |
| kv over a real socket | 15k GETs/s, 10k SETs/s |
| decision-log rows | 150 |

## What Fable learned

- The corpus as acceptance test is the reason every step landed first time; keep it.
- Workers find the spec's holes better than we do; their gap lists are the second-best artifact after the code.
- The interpreter's memory model, not the language, was the whole cost of the first real programs.
- Two defaults a worker chooses per hour need ratifying; about one in twenty deserves overturning, and the log makes that cheap.

## Next

`HANDOFF.md`.

## Related
- [[session-04]]
- [[decision-log]]
- [[roadmap]]
- [[model-bakeoff]]
- [[corpus]]
- [[interpreter-step-1]]
- [[interpreter-step-2]]
- [[interpreter-step-3]]
- [[interpreter-step-4]]
- [[interpreter-step-5]]
- [[interpreter-step-6]]
- [[interpreter-step-7]]
- [[interpreter-step-8]]
- [[interpreter-step-9]]
- [[interpreter-step-10]]
- [[interpreter-step-11]]
- [[interpreter-step-12]]
- [[interpreter-step-12b]]
- [[interpreter-step-13]]
- [[interpreter-step-14]]
- [[interpreter-step-15]]
- [[interpreter-step-16]]
- [[control-run-3]]
- [[interpreter-step-17]]
- [[interpreter-step-18]]
- [[program-4]]
- [[interpreter-step-19]]
- [[interpreter-step-20]]
- [[control-run-4]]
- [[outside-review-2026-09-13-response]]
- [[research-agenda-2026-09-response]]
- [[program-2]]
- [[program-3]]
- [[control-run]]
- [[control-run-2]]
- [[q18-main-and-the-platform]]
