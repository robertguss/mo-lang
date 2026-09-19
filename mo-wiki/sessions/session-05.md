---
title: "Session 5 — 12–15 Sep 2026"
created: 2026-09-12
updated: 2026-09-17
type: session
tags: [meta, compiler, syntax, agents, runtime]
sources: [spec/grammar.md, plans/corpus.md, plans/model-bakeoff.md, plans/control-run-2.md, decisions/decision-log.md]
date: 2026-09-12
session: 5
---

# Session 5 — 12–15 Sep 2026 (this page runs to the night of 15 Sep; sessions 6 and 7 are in `CHANGELOG.md`)

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
- Robert, going to bed: run the queue as last night, every decision Fable's; no syntax tonight (the one-line `if` waits for the morning). [[interpreter-step-21]]: a process is a fiber, not an OS thread, in both runtimes; 65,530 idle connections from about 8,000; a process at rest half its size; the socket rows faster; chapter 7's bets measured; `Fs.fixture()` refuses `..`; three diagnostics with a `mo fix`. Fable's probe found HTTP backpressure counting request-less connections at about 1,000, flagged for program 1.
- [[program-1]]: `jobq`, the founding premise's first real test, in 40 minutes; nine modules; native 4,051 lease-and-ack pairs a second with 32 workers; Fable's 29-check session green under both runtimes. Found: literal deadlines lie where they nest (two of three derived sums were once wrong), `invariant` kept none of eight candidates (for Robert), the Q16 ledger empty, one `--recipe` bug, five gaps, nine runtime-surface questions on d37.
- [[control-run-5]], the first pre-registered round: Mo 14.8 min to Go's 11.6 and Python's 14.9, 1.28 times Go from 1.73; loops 5/2/3; P1 and P3 held, P2 missed by one loop; mixed. The laws stay.
- [[interpreter-step-22]]: the derived deadline, `reply_by` and `at_most`, in both runtimes and the simulator, jobq's three hand-written sums gone; the `--recipe` line count, the fixture's missing folder, `json.to_i64`, the recipe's rewrite rule with notes following it, two diagnostics; verified by Fable's probes in all three modes.
- [[interpreter-step-23]]: the runtime surface, directions 37 and 40 built: the event ring, `platform.runtime` as a capability with `read_only`, `mo run --surface PORT`; six of jobq's nine questions answered in full; Fable's probes green under both runtimes.
- [[program-5]]: `agent`, the harness under permissions, budgets, and retries, in 77 minutes; native 448.7 five-step runs a second; Fable's 22-check session green under both runtimes. Found: an authority hole in `MO0404`, the handle law forcing one routing process for the third program running (Fable's call: a `state` field may hold a handle, for Robert's eye), a third ask for a timer (Fable's call: `delay:` on `send`), two invariants kept.
- [[interpreter-step-24]]: the authority hole closed, a handle in a `state` field (a registry routes to a process per key), the delayed send three programs asked for, `Deadline.remaining`, four gaps; Fable's probes green under both runtimes.

## Day (14 Sep, from 12:30 UTC, the exe.dev VM)

- The lead resumed on the exe.dev Linux VM, not the Mac: Zig 0.16 installed with `mise`, the worker in Herdr pane `w7:p7`. Part A of step 25 had reached the remote from the Mac at 08:04 EDT; a fresh worker took it from there.
- The toolchain's first run on Linux: three suite failures, fixed as part F, none the epoll poller's; the carried "Linux poller never ran" item is cleared.
- [[interpreter-step-25]]: the one-line `if` as a value (pick 16) in both runtimes, the formatter choosing the shape, `mo fix` reversed, 25 one-line values in the corpus; `state` and `old` as a struct's field; the `if` and `case` authority hole closed; `agent` narrowed to spec 05 again. Fable's probes green under both runtimes. One finding for step 26: the form in tail position of a body is refused while the block form there is the value.
- [[interpreter-step-26]]: tail position is the value, the keyword sentence for `state` and `old` as names; 185 of 185. [[control-run-6]] pre-registered: two tasks, the baselines with their checks bolted on, the null hypothesis as P3.
- [[control-run-6]] run and read: **failed on all four predictions**. Mo 1.58 times Go over both tasks; Mo's loops the language's (keywords, a `case` arm form, the 500-line law, a false `never` trip), the baselines' the tools'; no check caught a real bug in any language, so the null hypothesis stands; Mo's jobq program longer than Go's. Robert (afternoon): Python tools live in the project's venv through `uv`, never globally. Three rows for Robert; no seventh round until one lands.
- Robert agreed to all three; reframed the control run around reliability, native speed, the feedback loop, and dependencies (chapter 8, Session 6); asked for a hidden defect suite and, later, a real open-source tool reimplemented in Mo against its own tests. [[interpreter-step-27]] built the three calls plus the escape and `fold_lines`, 185 of 185, Fable's probes green. [[control-run-7]] pre-registered on the new measure; its 121-check suite run after the fact on round 6's programs: Mo 0, Python 0, Go 1.
- Robert's outside review of the vault, filed with Fable's response and two replies; the thesis restated in chapter 1 (the runtime, then capabilities and recipes, then the language as their surface; the BEAM as the null hypothesis). [[control-run-7]] run and read: **held on all four** on Robert's measure; reliability level at 0 defects each; native Mo 981 pairs a second at 32 workers to Go's 478; the loop 0.38 s to 18.7; 0 dependencies to 1 and 3; agent time 74.6 min to 36, recorded only. Four toolchain bug notes and six gaps to step 28.
- [[interpreter-step-28]]: a map written in place by a move analysis shared by both backends (47 s → 0.13 s on the 80k map), the tuple accumulator moved, the `never` rule through branches, regions giving pages back (memory after a replay 183 → 57 MiB), six gaps; 186 of 186; Fable's probes green. Program 6 started at 23:52 UTC.
- [[program-6]]: the ledger in 92 minutes, 14 modules; four invariants kept, three tripped by tests over a torn or doubled log, the planted bug caught by a `never` and an invariant; native 1,168 transfers a second at 32 clients; Fable's 35-check session green under both runtimes. Found: `restart: :never` not honoured, `platform.exit` waiting on a delayed send, replay memory superlinear (1M entries killed at 4.2 GB), and no check earning its keep strictly for the third program. Robert asked for a stop and a discussion before round 8.
- The forest: Fable's reading of the three days for Robert (the claim not yet earned, the runtime the bottleneck, first writing the only thing measured) and Robert's go-ahead on Fable's order; the roadmap rewritten from here: step 29, step 30, round 8 as a maintenance round, the bricks page, the language items, program 7.
- [[interpreter-step-29]] (15 Sep, morning): the runtime honest: `restart: :never` kept in both runtimes with its report, `exit` past a pending delayed send, replay compacting in generations (1M native 716 → 81 s, the peak now the book's own 2.5 GB), simulated time only when a test waits, `invariants (kept n, tripped m)` on the `verified:` line; Fable's probes green under both runtimes; ten rows, one open (an overflow in a `test rejects` fails rather than rejects). Fable's 1M probe on a real HTTP-written log passed 8 GB after the fold: [[interpreter-step-29b]] briefed and started.
- [[interpreter-step-29b]] (15 Sep, midday): where the replay's memory went (a 1 GiB region filled in one update, then malloc forever), address space reserved, the walk through waiting frames; the real 1M log 2.3 GB where it was killed past 9; five rows. Robert's small-model round as [[d41-small-model-round|direction 41]].
- Robert, midday: direction 41 locked (round 9 after round 8, several models, the Pi harness, his subscriptions); pause after round 8 to plan round 9 together; this session closed with the handoff rewritten whole.
- [[interpreter-step-30]] (15 Sep, afternoon and evening): processes on every core in both runtimes, the fsync on a thread pool, the same seeds the same traces; two 4-core bugs found by measuring; the queue fsync-bound on this disk, the ledger doubled, CPU-bound work 3.7× at 4 cores; accepted 20:05 with the lead's own kill client and replay. Robert's evening: the Mac run in parallel, the conjunction rule, the Elixir round (d42), runtime first then the language page; Fable's direction 43.

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

## Session 7, night of 15 Sep (the same page, the same branch)

Round 8's change spec, pre-registration, worktrees, and suites; measurement 2 run first in one pane: five regenerations of the board identical over 132k operations, one crash-versus-skip disagreement on a hand-made log ([[sampling-as-verification]], [[control-run-8]]). Five decision rows. Then round 8 itself, 22:22 to 23:35: held on all five, the conjunction survives, the laws' value for the second agent still unshown, an outage found by the fourth oracle ([[control-run-8]]). The pause.

## Next

`HANDOFF.md`.

## Astra overnight harness checkpoint — 19 Sep 2026, 1:06 AM ET

[[mo-executor-foundation]] passed independent acceptance after the lead found
and the Astra/low worker corrected premature reaper disarm. Lead results:
15 unit tests, 17 live controls, collector-death fault control and explicit
exit-137 control all passed. Cleanup and shared Mac Docker identity comparisons
are retained under `audit/evidence/2026-09-19/harness-integration/`.

Auth generated closure advanced the full suite from 241/243 to 242/243; three
formatting failures remain assigned. Provider fresh setup reproduced a missing
cache directory and is assigned back. A fresh Astra/low worker now implements
[[mo-coding-fixture-v1]]. No live credentials/inference or application repair
acceptance; Step 39 and Program 7 remain unchanged.

## Offline provider accepted — 19 Sep 2026, 1:16 AM ET

[[mo-provider-foundation]] passed independent clean setup, 28 actual-parser
cases and two extra controls, with original evidence unchanged. Source/artifact
mismatch and the SSE observation hook remain explicit. No live authentication
or Mo bridge is claimed. Linux trusted build preparation hit its memory cap
with two jobs; the same resource bound now runs one job. A fresh read-only
worker is reviewing the next isolated workspace slice while coding-fixture
implementation and the auth full-suite recheck continue.

## Terminal-auth accepted — 19 Sep 2026, 1:19 AM ET

[[mo-agent-terminal-auth]] passed final lead full-suite verification at e3a01bb:
243/243 tests, 5/5 steps, exit 0. All 62 changed files match the reviewed worker
tip; shared recipe bytes stay unchanged. Earlier 241/243 and 242/243 failures
remain, alongside 18 HTTP cases and six extra lead controls. Three local
foundations are accepted; coding-fixture and Linux build work continue.

## Published checkpoint and continued integration — 19 Sep 2026, 1:45 AM ET

Three foundations were pushed at 2fc1235 and wiki run 35423902551 succeeded.
Coding fixture review reproduced a native report-before-last-step race and
positive-token cancellation; corrected local matrices pass, integration pending.
Workspace controls and lifecycle regressions pass; final correction is running.
Native Linux builds reached memory/time bounds with positive cleanup; a trusted
Mac cross-build passed but Linux execution is still unverified. A fresh bounded
[[mo-provider-auth-v1]] slice will prepare private device OAuth using fixtures.
No live credentials, application acceptance or retired audit gate is implied.

## Astra application-boundary checkpoint — 19 Sep 2026, 2:34 AM ET

Coding fixture accepted at e6f04ce after cold-runner correction: full243/243,
5/5, both runtime matrices and lead controls. Workspace passed27 unit/22 live/
17 executor/lifecycle/two extras with empty cleanup. Private auth passed28 auth/
28 provider/two extras after a retained late-response-body red. Worker panes
closed after idle receipts; historical worktrees and every failure remain.

Provider bridge accepted at191da144:27 protocol groups, real Mo both runtimes,
28 provider/two extras, full243/243 and5/5;3489 tracked files unchanged. Mixed Mo
selection corrected separately. Published5e568227/wiki35426384194 passed.
Application worker owns dedicated machine/image work after exact outer/parent
cgroup readback and release. Remote wire review flags identity/encoding/budget
compatibility for the next slice. No live inference or application-repair claim.

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
- [[interpreter-step-21]]
- [[program-1]]
- [[control-run-5]]
- [[interpreter-step-22]]
- [[interpreter-step-23]]
- [[program-5]]
- [[interpreter-step-24]]
- [[program-2]]
- [[program-3]]
- [[control-run]]
- [[control-run-2]]
- [[q18-main-and-the-platform]]
