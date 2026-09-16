---
title: "Roadmap"
created: 2026-09-12
updated: 2026-09-15
type: plan
tags: [roadmap]
sources: [plans/program-menu.md, spec/design-v0/08-milestone.md]
status: in-progress
---

# Roadmap

Rewritten in session 5 after the interpreter milestone was met. Each step is one brief on a plan page, one fresh worker session, Fable's verification, one commit that updates [[decision-log]], `CHANGELOG.md`, and `log.md`, then a merge to `main`. Done steps keep their rows.

## Where we are

Rewritten 15 Sep 2026 after program 6, when Robert asked for the forest and agreed to Fable's order. The rows above the line are what the first three days built; the rows below are the roadmap from here. A step is one brief to one fresh worker session; this table is the count.

| phase | status | briefs left, roughly |
|---|---|---|
| The design, the corpus, the interpreter milestone (sessions 1–5) | done | — |
| The toolchain under real programs (steps 5–28): formatter, stdlib, `Net`, `Http`, the C backend, fibers, the runtime surface, the derived deadline, the delayed send, the one-line `if`, the keywords as names, a `never` at rest, a map written in place | done | — |
| Programs 1–6: jobq, logstat, kv, notes, agent, ledger | done; each found two to four toolchain bugs and several gaps | — |
| Control rounds 1–7: rounds 1–6 on agent time (Mo slower, round 6 failed on all four), round 7 on Robert's measure (held on all four; reliability level at 0 defects each) | done | — |
| Outside reviews of 13 and 14 Sep, the thesis restated (chapter 1), the measure restated (chapter 8), the closure audit, the reading pack; Fable's earlier readings ([[empirical-validation-plan]], [[ecosystem-strategy]], [[research-agenda-2026-09-response]]) | done | — |
| Step 29, the runtime honest ([[interpreter-step-29]]): `restart: :never` honoured, `platform.exit` with a pending delayed send, replay streamed instead of held in one `Open` update, the simulated-time jump gap, the `invariant`-untrippable rule as a diagnostic | done 15 Sep; part C's memory bound unmet on a real log | — |
| Step 29b, replay memory on a real log ([[interpreter-step-29b]]): Fable's acceptance probe replayed a 1M log an HTTP session wrote and passed 8 GB fifteen seconds after the fold, where the worker's generated log peaked at 2.5 GB; the rule made to hold in every loop shape | done 15 Sep; the evidence log replays at 2.3 GB where it was killed past 9 | — |
| **Step 30, processes on every core** ([[interpreter-step-30]]): a scheduler per core, messages across threads, the store's fsync off the scheduler, measured against Go on the queue and the ledger | done 15 Sep, accepted; the queue is fsync-bound on this disk (round 8 reruns the baselines on it); the ledger doubled from the fsync pool; CPU-bound work 3.7× at 4 cores; two 4-core bugs found by measuring | — |
| **Round 8, the maintenance round** ([[control-run-8]]): round 7's three finished job queues handed to fresh agents with a changed spec; a second hidden suite for the change; defects and regressions counted; the experiment the laws were written for | done 15 Sep, night: held on all five (regressions 0/0/0, defects 0/1/0, 1,420 pairs a second against 428 and 325, the loop 0.81 s against 14.4 and 7.5, 0 dependencies); the conjunction survives, the laws' value for the second agent still unshown (no check caught a bug, Mo 2.2× Go's time); the fourth oracle found an outage on an impossible log record, for Robert | — |
| **Round 9, the small-model round** ([[d41-small-model-round|direction 41]], Robert, 15 Sep): the same pre-registered task and hidden suite with a small model in all three panes, several models of different sizes, open-weights ones among them (Robert, locked); reliability and loops are the columns that move with the model | queued, after round 8 | 1 plan, one session per model per language |
| **Round 10, the Elixir round** ([[control-run-10]], [[d42-elixir-round|direction 42]]): the BEAM null hypothesis run; round 7's job queue and round 8's change in Elixir with dialyzer, credo, and ExUnit, the same suites | done 16 Sep, night (brought forward): 2 defect causes against Mo's 0, twice Mo's speed at 32 workers, the loop 7 s against 0.8, zero run-time dependencies, half Mo's time to write; the null hypothesis alive, P6 (a crashed process, the service answering) still to probe on both | the P6 probe |
| **Measurement 1, bodies as cache** ([[bodies-as-cache]], direction 43): every program regenerated from its stripped spec, twice | five of six done 16 Sep, night: ten regenerations, ten at completeness 1.0 (logstat, kv, notes, jobq with the hidden suite, ledger); the agent program is next, then the form with the tests deleted | 2 runs, then the stronger form |
| **The bricks page** (`deep-dives/bricks-and-the-cost-of-zero-dependencies.md`, to be written): the shelf (TLS, crypto, compression, a database driver, HTTP/2), an audit budget per brick, the ordering rule, the fallback (a brick wrapping a C library in the platform under audit, never application FFI), a decision row | queued, Fable writes it | — |
| **The language after the rounds** (`spec/design-v0/09-language-after-the-rounds.md`, Fable writes it at the pause after round 8): one section per candidate change the runtime's evidence supports, each with the round row that motivates it, its cost, and code options for Robert: deadlines carried by the process or the message type; the failure model stated on the process declaration and checked at the caller; placement left out until a program needs it; the runtime surface as a capability; and the laws that cost loops without catching bugs removed. Zero new syntax stays the default; no change without a control-run row behind it. Robert's locked language items fold into it | queued, the pause after round 8; the rounds' evidence is its input | 1 page, then one step per accepted section |
| The language items Robert agreed to (now sections of the page above): the counted shape laws as project settings; a named function passed by name where an anonymous function goes; the grammar forms that cost loops in every program (`return` in a `case` arm, a qualified call, a split lambda body) as diagnostics that say what to write; the `invariant` construct reconsidered after round 8 | queued, one step after round 8 | 1 |
| A compile benchmark at 5,000 generated modules (the agent-loop claim at scale) | queued, small | 1 |
| Program 7, a real open-source service reimplemented against its own test suite (a Redis subset with streams, persistence, auth, pub/sub, its operation set pre-registered from Redis's own tests), once a program finishes with no new gap or bug note | after round 8 | 2 |
| Tier 3 proving, `mo prove` | queued | 2–3 |
| The package registry | deferred until an outsider runs a real service | — |
| Program 8, the toolchain in Mo | late | — |

Six to eight briefs to round 8's reading, at about an hour of worker time each plus verification; program 7 and `mo prove` after it.

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
| 33 | done: step 29b: memory bounded by what an update reaches, in every loop shape; a process region reserves address space and a walk compacts the frames waiting in calls; the real 1M log replays at 2.3 GB where it was killed past 9 ([[interpreter-step-29b]]) | step 30 |
| 32 | done: step 29: `restart: :never` honoured with its report, `exit` past a delayed send, replay compacting in generations (1M native 716 → 81 s), simulated time only when a test waits, invariants counted on the `verified:` line; Fable's 1M probe on a real log passed 8 GB after the fold, to [[interpreter-step-29b]] ([[interpreter-step-29]]) | step 29b |
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
