---
title: "Roadmap"
created: 2026-09-12
updated: 2026-09-12
type: plan
tags: [roadmap]
sources: [plans/program-menu.md, spec/design-v0/08-milestone.md]
status: in-progress
---

# Roadmap

Rewritten in session 5 after the interpreter milestone was met. Each step is one brief on a plan page, one fresh worker session, Fable's verification, one commit that updates [[decision-log]], `CHANGELOG.md`, and `log.md`, then a merge to `main`. Done steps keep their rows.

## Done

| step | what | evidence |
|---|---|---|
| 1–3 (sessions 1–3) | the wiki, design v0, the grammar, 13 comparisons | `mo-wiki/` |
| 4 (session 5) | the corpus, 52 programs, three-model bake-off | [[corpus]], [[model-bakeoff]] |
| 5.1–5.4 (session 5) | lexer, parser, tier-1 checker, VM, tier-2 contracts, test runner, processes, supervisors, `Mo.Sim` scheduler: **the milestone** | [[interpreter-step-1]] … [[interpreter-step-4]], `08-milestone.md` |

## Next, in order (the overnight run of session 5 starts here)

| step | what | measures |
|---|---|---|
| 5.5 | the formatter, `mo fmt`, loop rule as a diagnostic | one shape for every file |
| 5.6 | `main` and `Mo.Server`: Mo runs programs ([[q18-main-and-the-platform]]) | three programs with expected output |
| 6 | **program 2, the CLI log analyzer, written in Mo by a worker from a spec**; Robert reads the spec altitude only | loops to green, gaps hit, lines per function |
| 6c | the control run: same spec in Go and Python, same worker | chapter 8's null hypothesis, first number |
| 7 | the stdlib chapter: every gap becomes a built-in and a row | stdlib misses per program |
| 8 | `Mo.Sim` seeds and fault injection; `sim (N runs)` real | counterexamples found |
| 9 | `verified:` written to the file via the sidecar; `mo fix` for the loop rule | hand-edit detection |
| 10 | the error catalog from the codes; the README front door | a model that has never seen Mo |
| 11 | program 3, the KV store over TCP | hot loops, overflow-check cost |
| 12 | the C backend via Zig for release, differential-tested | single binary; speed |
| 13 | program 1, the job queue, once the platform has HTTP and a store | the founding premise at scale |
| 14 | the package registry ([[d34-packages-are-recipes]]); `mo prove` | later |

## Session 3 note

Robert: `spec/design-v0` is a folder of files, one per chapter. Kept.

## Related
- [[program-menu]]
- [[q14-first-real-program]]
- [[q13-implementation-language]]
- [[session-05]]
- [[decision-log]]
- [[comparison-pass]]
