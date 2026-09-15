---
title: "Roadmap"
created: 2026-09-12
updated: 2026-09-14
type: plan
tags: [roadmap]
sources: [plans/program-menu.md, spec/design-v0/08-milestone.md]
status: in-progress
---

# Roadmap

Rewritten in session 5 after the interpreter milestone was met. Each step is one brief on a plan page, one fresh worker session, Fable's verification, one commit that updates [[decision-log]], `CHANGELOG.md`, and `log.md`, then a merge to `main`. Done steps keep their rows.

## Where we are

Updated at every acceptance. A step is one brief to one fresh worker session, numbered in the order it ran, not a count toward an end; this table is the count.

| phase | status | briefs left, roughly |
|---|---|---|
| The design, the corpus, the interpreter milestone (sessions 1–5) | done | — |
| The toolchain under real programs: formatter, stdlib, `Net`, `Http`, the C backend, three review rounds (steps 5–18) | done | — |
| Programs 2, 3, 4: logstat, kv, notes | done | — |
| Step 19, what program 4 found | done | — |
| Step 20, the runtime owns the loop | done | — |
| Round 4 of the control run | done: Mo 16.1 min to Go's 9.3; laws kept, an ergonomics step recommended | — |
| Fable's reading: the session 6 runs read ([[empirical-validation-plan]], [[ecosystem-strategy]]); the research agenda's twelve pages answered ([[research-agenda-2026-09-response]]); the VM-first drafts filed (d36–d40) | done | — |
| Memory and green threads (chapter 7), [[interpreter-step-21]] | done: a process is a fiber, 65,530 connections, the bets measured | — |
| Program 1, the job queue ([[program-1]]): done, 40 min, the premise held; its follow-ups (step 22: the `--recipe` line count, the fixture's missing folder, JSON integers, a derived deadline, the recipe's rewrite rule) | done: [[interpreter-step-22]], the derived deadline | — |
| Round 5 of the control run, pre-registered ([[control-run-5]]) | done: mixed, Mo 1.28 times Go, P2 missed by one loop | — |
| The runtime surface (directions 37 and 40), [[interpreter-step-23]] | done: `platform.runtime`, the event ring, `--surface` | — |
| Tier 3 proving, `mo prove` | queued | 2–3 |
| Program 5, the agent harness ([[program-5]]): done, 77 min; its follow-ups, [[interpreter-step-24]] | done: the authority hole, a handle in state, the delayed send | — |
| Step 25, the one-line `if` and keyword field names (Robert's calls, [[interpreter-step-25]]) | done: the value form in both runtimes, 25 on one line in the corpus, the first Linux run green | — |
| Step 26, the tail-position one-line `if` and two keyword diagnostics ([[interpreter-step-26]]) | done | — |
| Round 6 of the control run, pre-registered ([[control-run-6]]), the baselines with their checks | done: **failed on all four predictions**; the null hypothesis stands; three rows for Robert | — |
| Step 27, what round 6 found (Robert agreed to all three: the file law gone, the keywords as names, a `never` reads values at rest; [[interpreter-step-27]]) | done | — |
| Round 7 ([[control-run-7]]), on Robert's measure | done: **held on all four**; reliability level at 0 defects each; Mo fastest at 32 workers, slowest to restart; the loop 0.38 s; 0 dependencies | — |
| Step 28, round 7's toolchain notes ([[interpreter-step-28]]) | done: a map written in place (47 s → 0.13 s), memory after replay 183 → 57 MiB, six gaps | — |
| Program 6, the ledger ([[program-6]]) | done: 92 min, four invariants kept, the planted bug caught twice, no check earned its keep strictly, a `restart: :never` bug found | — |
| Round 8, the ledger against Go and Python on Robert's measure with a hidden suite | next, not started (Robert's discussion first) | — |
| The next runtime step: `restart: :never` honoured, `platform.exit` with a pending delayed send, replay memory, processes on more than one core | queued | 1–2 |
| The package registry | deferred until an outsider runs a real service | — |
| Program 7, a real open-source service reimplemented in Mo against its own test suite, chosen so the original carries third-party dependencies and the Mo version exercises capabilities, recipes, and the runtime surface (Robert, 14 Sep; the thesis restated) | after program 6 passes the readiness rule (no new gap or bug note) | 2 |
| Program 8, the toolchain in Mo | late | — |

About ten to fifteen briefs to the end of the roadmap as written, at roughly one an hour of worker time plus verification. A program that finds a runtime hole adds one; round 4 may send a law back.

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
| 14 | done: follow-ups, contracts in every build, formatter shapes, stdlib rows ([[interpreter-step-14]]) | round 3 of the control run |
| 15 | done: processes and `Net` in the C backend; native kv 1.4× the interpreter at half the memory ([[interpreter-step-15]]) | — |
| 16 | done: HTTP in the stdlib, native httpd 1.7× the interpreter ([[interpreter-step-16]]) | — |
| 16b | done: round 3 of the control run; Mo's checks caught a real bug, six syntax loops, timing void ([[control-run-3]]) | — |
| 17 | done: round 3 follow-ups ([[interpreter-step-17]]) | — |
| 18 | done: the outside review's no-compat fixes ([[interpreter-step-18]], [[outside-review-2026-09-13-response]]); the failure model in chapter 3 | — |
| 18b | done: program 4, `notes`; native 23,692 gets/s with 32 clients; the recipes saved a design and exposed the conformance gap ([[program-4]]) | — |
| 20 | done: the runtime owns the loop, 11 fictional bounds → 0, every expected file unchanged ([[interpreter-step-20]]) | — |
| 20b | done: round 4, timing valid, Mo 16.1 min to Go's 9.3 and Python's 9.0, loops 5/1/0, the laws kept ([[control-run-4]]) | round 5 after program 1 |
| 21 | done: green threads in both runtimes, 65,530 idle connections from 8,000, a process at rest half its size, the four chapter 7 bets measured, `Fs.fixture()` refuses `..`, three diagnostics ([[interpreter-step-21]]) | program 1 |
| 19 | done: what program 4 found; 200,000 processes at 9 MB native, the deadlock a report, `--recipe`, mutation tests 9 of 10 ([[interpreter-step-19]]) | — |
| 31 | done: program 6, `ledger`, 92 min, 14 modules, 1,168 transfers a second native; four invariants kept; a `restart: :never` bug ([[program-6]]) | round 8 |
| 30 | done: step 28: a map written in place by a move analysis in both backends, the tuple accumulator moved, the `never` rule through branches, regions giving pages back, six gaps ([[interpreter-step-28]]) | program 6 |
| 29b | done: round 7, pre-registered on Robert's measure, held on all four ([[control-run-7]]) | step 28, program 6 |
| 29 | done: step 27: the file law gone, `state`/`result`/`old` as names, a `never` reads values at rest, `\u{X}`, `fold_lines` past a bad line ([[interpreter-step-27]]) | round 7 |
| 28b | done: round 6, pre-registered, failed on all four predictions: 1.58 times Go, a shape-law loop, no check caught a bug in any language, 0.74 of Go's lines ([[control-run-6]]) | Robert's reading of the laws |
| 28 | done: step 26: the one-line `if` in tail position is the value, the keyword sentence for `state` and `old` as names ([[interpreter-step-26]]) | round 6 |
| 27 | done: step 25: the one-line `if` as a value in both runtimes, `state` and `old` as field names, the `if` hole closed, `agent` narrowed to its spec, the suite's first Linux run green ([[interpreter-step-25]]) | step 26, round 6 |
| 26 | done: step 24: the read-only `Fs` hole closed, a handle in a `state` field, `delay:` on `send`, `Deadline.remaining` ([[interpreter-step-24]]) | program 6 |
| 25 | done: program 5, `agent`, 77 min, 19 modules, 448.7 five-step runs a second native, verified by a 22-check session ([[program-5]]); the budget model works where an asker exists; an authority hole and the handle law's cost found | step 24, round 6 |
| 24 | done: step 23, the runtime surface: `platform.runtime`, the event ring, `mo run --surface`; six of jobq's nine questions answered in full ([[interpreter-step-23]]) | program 5 |
| 23 | done: step 22, the derived deadline `reply_by` in both runtimes, jobq's hand-written sums gone, the `--recipe` line count, the recipe's rewrite rule ([[interpreter-step-22]]) | program 5 |
| 22b | done: round 5, pre-registered, mixed: Mo 14.8 min to Go's 11.6 (1.28, from 1.73), loops 5/2/3, no shape-law loop ([[control-run-5]]) | round 6 after program 5 |
| 22 | done: program 1, `jobq`, 40 min, nine modules, 4,051 lease-and-ack pairs a second native, verified by a 29-check session ([[program-1]]); literal deadlines lie where they nest; `invariant` kept none of eight candidates | round 5, step 22 |
| 19 | the package registry ([[d34-packages-are-recipes]]); `mo prove` | later |

## Session 3 note

Robert: `spec/design-v0` is a folder of files, one per chapter. Kept.

## Related
- [[program-menu]]
- [[q14-first-real-program]]
- [[q13-implementation-language]]
- [[session-05]]
- [[decision-log]]
- [[comparison-pass]]
