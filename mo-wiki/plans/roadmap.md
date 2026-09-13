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
| 5.5 | done: the formatter | [[interpreter-step-5]] |
| 5.6 | done: `main` and `Mo.Server` | [[interpreter-step-6]] |
| 6 | done: program 2, `logstat`, in Mo from a spec | [[program-2]] |
| 6c | done: the control run in Go and Python | [[control-run]] |
| 7 | done: programs of many modules, memory, speed | [[interpreter-step-7]] |
| 7b | done: the stdlib, `09-stdlib.md` | [[interpreter-step-8]] |
| 8 | done: `Mo.Sim` seeds and faults | [[interpreter-step-9]] |
| 9, 10 | done: sidecar, `mo fix`, error catalog, README | [[interpreter-step-10]] |
| 11 | done: `Net`, program 3 `kv`, the runtime under real programs, two defaults undone | [[interpreter-step-11]], [[program-3]], [[interpreter-step-12]], [[interpreter-step-12b]] |
| 12 | done: control run round 2, Mo 11.8 min from 25.5 | [[control-run-2]] |
| 13 | done: the C backend, native logstat 7× the interpreter | [[interpreter-step-13]] |
| 14 | follow-ups: contracts in every build, formatter shapes, stdlib rows ([[interpreter-step-14]]) | round 3 of the control run |
| 15 | processes and `Net` in the C backend; kv as a native binary | requests per second, native |
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
