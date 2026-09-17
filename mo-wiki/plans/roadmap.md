---
title: "Roadmap: now, next, later"
created: 2026-09-12
updated: 2026-09-17
type: plan
tags: [roadmap]
sources: [plans/program-menu.md, spec/design-v0/08-milestone.md]
status: in-progress
---

# Roadmap

The board first: what is in flight, what comes next in order, what waits, what
just landed. One line each, with the page that holds the detail. Fable rewrites
it at every acceptance and every pause; the dates say when. Below it, the phases
in detail and the history of every step.

## Now, in flight

| what | who | since | page |
|---|---|---|---|
| Step 35, the crypto brick: one Opus session on [[interpreter-step-35]] on the VM (pane `w7:pJ`; the Mac worker of 16:05 ended before writing, on Robert's ask); Fable verifies with the differential run, the hour of fuzzing, and its own probes | worker | 17 Sep, 15:50 UTC | [[interpreter-step-35]] |

## Next, in order

| # | what | why now | page |
|---|---|---|---|
| 1 | The crypto brick (one step: SHA-256, SHA-512, HMAC, HKDF, AES-GCM, ChaCha20-Poly1305, X25519, Ed25519, Argon2id, a CSPRNG; written once in Zig, linked into both runtimes; the five audit items) | program 7 needs SHA-256 for ACL passwords; TLS needs the rest | [[bricks-and-the-cost-of-zero-dependencies]] |
| 2 | A probe naming the cause of generation four's nine-times loss in the Mo queue (quiet machine, `sample` under load) | the runtime rule's speed row (RC2) is at its line on today's record; a red cost row decides the claim | [[erosion-round]] |
| 3 | The TLS brick (two steps: a TLS 1.3 server on Zig's client code; the certificate chain and the differential run against OpenSSL) | program 7's listener; Redis's suite runs with `--tls` | [[bricks-and-the-cost-of-zero-dependencies]] |
| 4 | Program 7: a Redis subset against Redis's own tests, with TLS, hashed ACL passwords, and a metrics endpoint. Fable's sealed spec, then the auditor's pre-registration (Robert opens it: the hidden suite of 50 or more, the wait probe, the abuse suite, the drift seeds, the P4 change), then the Mo and Elixir builds | the pre-registered test of the primary claim (chapter 1, M-3) | [[program-menu]], [audit/](https://github.com/robertguss/mo-lang/blob/main/audit/README.md) |
| 5 | Change 6 and generation six (may run while program 7 waits on the auditor's seal, never ahead of its build) | the language rule is read at generation ten | [[erosion-round]] |
| 6 | Placement for what `main` starts, and a unit test for the step-aside: the step 34 follow-up | `echo-1k` and the binary's `kv-10k-get` still slower at 14 cores by that rule | [[interpreter-step-34]] |
| 7 | Chapter 10's other sections as steps: §2 the restart budget diagnostic, §3 the counted laws to `mo.toml`, §5 MO0317 naming the changed module | decided on the language page, each with a round row behind it | [[10-language-after-the-rounds]] |
| 8 | The compile benchmark at 5,000 generated modules | the agent-loop claim at scale, small | — |

## Later

The compaction copy per reference (half again on jobq's log) and the one-second restart at 100,000 jobs; `mo prove` (tier 3); the runtime surface as MCP tools and measurement 4, the incident round, which tests whether the surface shortens an agent's diagnosis; round 9's Opus-in-Pi baseline when Pi has an Anthropic key; the package registry once an outsider runs a real service; program 8, the toolchain in Mo.

## Waiting on Robert

**Blocking program 7:** once the bricks page and program 7's spec land, an audit session opened by Robert to seal program 7's pre-registration (only Robert opens audit sessions).

Rows marked "for Robert" in the [[decision-log]], newest first: the bricks page's two rows (the shelf boundary and program 7's two bricks; the audit items, caps, and cost); the auditor role taken up, M-3 accepted, the bricks prerequisite, and three disagreements with the ratified rules (program 7's shape against the capabilities rule, the R-A trigger at zero catches, Fable's reading of the runtime rule's open clauses) (17 Sep, afternoon); research PR 2 read and merged, chapter 10's attribution corrected (17 Sep); generation five's reading, the first Mo-only defect, the laws still silent; the change 4 Mo queue nine times slower on the lease path, speed recorded per generation; generation four; chapter 10 §2's budget as a value; generation three, the BEAM's row answered; P6 on Mo's change 2; round 9's Haiku row and its reading; generation two; chapter 10 §1 as built (step 31); chapter 10 itself; P6 on Elixir; measurement 1's completeness row; the BEAM row after round 10; the outage, probed and read; round 8 read; the 16 lint issues from his history bundle. Apart from the audit session, none blocks the work: Fable decides and records, Robert overturns.

## Recently done

| when | what | page |
|---|---|---|
| 17 Sep, afternoon | The bricks page: the shelf boundary as three tests, the cost measured against Zig's `std` (about 70,000 lines to read, 12,000 to 15,000 to write, estimated), five audit items and a surface cap per brick, bricks written once in Zig for both runtimes, the vendored-C fallback; program 7 needs crypto and TLS | [[bricks-and-the-cost-of-zero-dependencies]] |
| 17 Sep, afternoon | The auditor role taken up: three stopping rules ratified by Robert, linked from chapter 1, chapter 10, and the state page; M-3 accepted; Fable's disagreements filed as rows | [audit/README.md](https://github.com/robertguss/mo-lang/blob/main/audit/README.md) |
| 17 Sep, morning | Research PR 2 (the Hermes lane, wiki only) read and merged: restart budgets, error-path coverage, crash consistency, capability confinement; chapter 10's 3-in-5 budget reattributed to Elixir `Supervisor`; `erosion2-*` and `erosion5-*` pushed at last | [[hermes-daily-2026-09-17]] |
| 16 Sep, 22:55 | Generation five: change 5 by four maintainers in 11 to 25 minutes; the sixth suite Python 94, Elixir 94, Go 92, Mo 93 of 94; the first Mo-only defect, the laws silent; the speed row per generation | [[erosion-round]] |
| 16 Sep, 21:20 | Step 34: placement with the starter, the crossing made cheap (100k asks across schedulers 4 s to 0.14), measured at 1, 4, and 14 cores; the change 4 Mo queue found nine times slower on the lease path | [[interpreter-step-34]] |
| 16 Sep, 17:05 | Change 5 sealed, generation five pre-registered: a lease handed off, a queue renamed with jobs in flight | [[01f-job-queue-change-5]] |
| 16 Sep, 15:05 | Generation four: change 4 by four maintainers; the fifth suite Mo 77, Python 77, Go 76, Elixir 76 of 77; nothing new eroded in four generations | [[erosion-round]] |
| 16 Sep, 13:03 | Change 4 sealed: idempotent creates, the archive | [[01e-job-queue-change-4]] |
| 16 Sep, 13:05 | Step 33: the crash report freed in both runtimes (46 MiB a restart to under 0.3), the interpreter's abort on a large log fixed | [[interpreter-step-33]] |
| 16 Sep, 11:20 | Generation three: change 3 by four maintainers in 10 to 23 minutes; the fourth suite Mo 55, Go 55, Python 55, Elixir 53 of 55; the Mo queue killed under load back in 106 ms, the BEAM's row answered | [[erosion-round]] |
| 16 Sep, 10:20 | Change 3 sealed: the store restarts itself, a budget, a chaos switch | [[01d-job-queue-change-3]] |
| 16 Sep, 10:20 | Step 32: crash reports kept apart from the ring, both runtimes; the reopening restart in the corpus; the P6 probe lists the crash with the default ring | [[interpreter-step-32]] |
| 16 Sep, 09:05 | P6 on Mo's change 2: the queue crashed under load through the surface, `503` within 2 ms, nothing lost, no restart; the outage closed, the restart the program's | [[erosion-round]] |
| 16 Sep, 08:45 | Round 9 closed with Haiku 4.5: wrong in every language in under ten minutes (Mo 28, Go 22, Python 18 of 189) | [[control-run-9]] |
| 16 Sep, morning | The wiki as a site, the state page, seven maps | [[state-of-the-project]] |
| 16 Sep, 02:00 | Erosion round, generation two: nothing eroded in Mo, Go, Python; Elixir refuses a torn line after a full disk | [[erosion-round]] |
| 16 Sep, 01:15 | Step 31, the deferred reply, in all three runtimes | [[interpreter-step-31]] |
| 16 Sep, 01:00 | Measurement 1 complete: twelve of twelve regenerations at 1.0 | [[bodies-as-cache]] |
| 15 Sep, night | Chapter 10, the language after the rounds; P6 on Elixir; the Mac scaling run; round 10 | [[10-language-after-the-rounds]], [[control-run-10]], [[mac-scaling-run]] |

## The phases in detail

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
| **Step 34, placement** ([[interpreter-step-34]]): a process an update starts placed with its starter, the cross-scheduler crossing made cheap, measured on the Mac at 1, 4, and 14 cores | done 16 Sep, 21:20, accepted: the queue's pairs and `kv-10k-get` under `mo run` level across cores, the crunchers 7.3×, `echo-1k` and the binary's `kv-10k-get` still slower at 14 by the main-starts rule; carried: placement for what `main` starts, a test for the step-aside, the compaction copy measured on the ledger | 1 (the follow-up) |
| **Step 30, processes on every core** ([[interpreter-step-30]]): a scheduler per core, messages across threads, the store's fsync off the scheduler, measured against Go on the queue and the ledger | done 15 Sep, accepted; the queue is fsync-bound on this disk (round 8 reruns the baselines on it); the ledger doubled from the fsync pool; CPU-bound work 3.7× at 4 cores; two 4-core bugs found by measuring. The Mac run (15 Sep, night): every row fastest at 1 core, the cross-scheduler ask the cost; placement is a step after 31 | 1 (placement) |
| **Round 8, the maintenance round** ([[control-run-8]]): round 7's three finished job queues handed to fresh agents with a changed spec; a second hidden suite for the change; defects and regressions counted; the experiment the laws were written for | done 15 Sep, night: held on all five (regressions 0/0/0, defects 0/1/0, 1,420 pairs a second against 428 and 325, the loop 0.81 s against 14.4 and 7.5, 0 dependencies); the conjunction survives, the laws' value for the second agent still unshown (no check caught a bug, Mo 2.2× Go's time); the fourth oracle found an outage on an impossible log record, for Robert | — |
| **Round 9, the small-model round** ([[d41-small-model-round]], Robert, 15 Sep): the same pre-registered task and hidden suite with a small model in all three panes, several models of different sizes, open-weights ones among them (Robert, locked); reliability and loops are the columns that move with the model | done 16 Sep, 08:45 ([[control-run-9]]), five of five models: reliability moved with the model on the Mo side for the cloud models (kimi 1, deepseek 2, gpt-5.5 0 defect causes; every Go change 1, every Python 0) and in every language for Haiku 4.5 (Mo 28 checks over 4 causes, Go 22 over 6, Python 18 over 2, in 7 to 9 minutes, none green by every check); the diagnostics carried the cloud models to green (first fix right in 21 of 23 loops); the local 27B made no edit in any language; P1 held, P4 for four of five, P2 (open-weights and Haiku), P3, P5 failed; the Opus-in-Pi baseline unmet | — |
| **The erosion round, generations two to five** ([[erosion-round]]): changes 2 to 5 to all four programs by fresh maintainers, a hidden suite per generation, the fourth oracle, P6, the speed row | generation two done 16 Sep, 02:00: nothing eroded in Mo, Go, Python on the old suites; Elixir refuses a torn line and cannot restart after a full disk; third suite Mo 65, Go 66, Python 65, Elixir 62 of 66. Generation three done 16 Sep, 11:20: change 3, the store that restarts itself; the fourth suite Mo 55 of 55 under both runtimes, Go 55, Python 55, Elixir 53; the Mo queue killed under load back in 106 ms (Elixir 285 to 694), nothing lost; P1, P2, P5 held, P3 and P6 half, P4 failed; nothing new eroded in three generations. Generation four done 16 Sep, 15:05: change 4, the key and the archive; the fifth suite Mo 77 of 77 both runtimes, Python 77, Go 76, Elixir 76; P1, P2, P5, P6 held, P3 and P4 failed; nothing new eroded in four. Generation five done 16 Sep, 22:55: change 5, the handoff and the rename, the seam a law; the sixth suite Python 94, Elixir 94, Go 92, Mo 93 both runtimes (the first Mo-only defect: a folder its own `verify` refuses after a compaction and a rename); P1 and P5 held, P2, P3, P4, P6 failed; the speed row per generation added, and generation four's Mo queue found nine times slower on the lease path | changes 6 to 10, one generation each |
| **Round 10, the Elixir round** ([[control-run-10]], [[d42-elixir-round]]): the BEAM null hypothesis run; round 7's job queue and round 8's change in Elixir with dialyzer, credo, and ExUnit, the same suites | done 16 Sep, night (brought forward): 2 defect causes against Mo's 0, twice Mo's speed at 32 workers, the loop 7 s against 0.8, zero run-time dependencies, half Mo's time to write; the null hypothesis alive; P6 probed on the Mac 15 Sep: the queue killed from outside three times under load, service back in under 600 ms each time, 0 acknowledged writes lost, the BEAM's row, bounded by the default restart intensity (four kills in 2 s and the node exits). P6 on Mo's change 2 (16 Sep, morning, [[erosion-round]]): the queue crashed by an input through the runtime surface under 10,000 requests a second, every request `503` within 2 ms from then, nothing acknowledged lost, no restart by the program's `:never`; the outage is closed, the restart is the program's to take (change 3), since a restarted process re-runs its state initializers. Change 3 took it (16 Sep, 11:20): the Mo queue killed under load back in 106 ms, nothing lost, against Elixir's 285 to 694 ms; the BEAM's P6 row is answered | — |
| **Measurement 1, bodies as cache** ([[bodies-as-cache]], direction 43): every program regenerated from its stripped spec, twice | done 16 Sep, 01:00: twelve of twelve regenerations at completeness 1.0 (logstat, kv, notes, jobq with the hidden suite, ledger, the agent program); the stronger form, tests deleted too, on logstat: 0.74 under the original tests, 1.0 under the transcripts | — |
| **The bricks page** ([[bricks-and-the-cost-of-zero-dependencies]]): the shelf boundary, the cost, five audit items and a cap per brick, the ordering rule, the fallback | done 17 Sep, afternoon; five rows; the crypto and TLS bricks are the steps before program 7 | 3 (crypto 1, TLS 2) |
| **The language after the rounds** (`spec/design-v0/10-language-after-the-rounds.md`, Fable wrote it 15 Sep on the Mac, after P6): one section per candidate change the runtime's evidence supports, each with the round row that motivates it, its cost, and code options for Robert: deadlines carried by the process or the message type; the failure model stated on the process declaration and checked at the caller; placement left out until a program needs it; the runtime surface as a capability; and the laws that cost loops without catching bugs removed. Zero new syntax stays the default; no change without a control-run row behind it. Robert's locked language items fold into it | the page written 15 Sep: six sections, two with a change (a deferred reply token, §1; the restart budget asked for on every `:always` child, §2), the counted laws as settings (§3), no change to `never` and `invariant` (§4), MO0317's rewrite (§5); §1 is the step that decides P6 for Mo, for Robert | one step per accepted section, §1 first |
| **Step 31, a deferred reply** ([[interpreter-step-31]]): chapter 10 §1 built: `Reply(T)`, `reply_to`, `answer`, in the checker and all three runtimes, a corpus file, the spec lines | done 16 Sep, 01:15, accepted: `Reply(T)`, `reply_to`, `answer`, MO0411, all three runtimes, the corpus file; the standing rows unchanged, the deferred reply level with send-and-a-message-back at 8 askers and 0.46 at 128 under `mo run` (the parked fiber, for the placement step); Fable's crash probe 8 of 8 `Down` then 8 answered | — |
| **Step 33, the crash report freed, and the interpreter's abort on a large log** ([[interpreter-step-33]]): the report freed after printing in both runtimes; the high-water mark fixed | done 16 Sep, 13:05, accepted: 46 MiB a restart to under 0.3 as a binary, 28 to 0 under `mo run`; the abort fixed with a unit test; unwritable, restart, budget green both runtimes; carried: the 1.45 s restart at 100,000 jobs, the compaction copy per reference | — |
| **Step 32, crash reports apart from the ring, and the reopening store** ([[interpreter-step-32]]): `/crashes` kept where load cannot evict it, both runtimes; a corpus file showing a restarted process reopening its store | done 16 Sep, 10:20, accepted: the last 16 reports in their own store, `--crashes N` and `MO_CRASHES=N`, newest first; `crash-kept.mo` and `restart-reopens.mo`; the probe lists the crash with the default ring; rows within noise; carried: the full reports both runtimes keep for a whole run, unbounded | — |
| The language items Robert agreed to (now sections of the page above): the counted shape laws as project settings; a named function passed by name where an anonymous function goes; the grammar forms that cost loops in every program (`return` in a `case` arm, a qualified call, a split lambda body) as diagnostics that say what to write; the `invariant` construct reconsidered after round 8 | superseded: these became chapter 10 §§2, 3, 5 and sit in the Next table as row 3 | — |
| A compile benchmark at 5,000 generated modules (the agent-loop claim at scale) | queued, small | 1 |
| Program 7, a real open-source service reimplemented against its own test suite (a Redis subset with streams, persistence, auth, pub/sub, its operation set pre-registered from Redis's own tests), once a program finishes with no new gap or bug note | Next, row 4 (M-3, 17 Sep): after the crypto and TLS bricks and the speed probe, before generation six's build | 2 |
| Tier 3 proving, `mo prove` | queued | 2–3 |
| The package registry | deferred until an outsider runs a real service | — |
| Program 8, the toolchain in Mo | late | — |

The Next table at the top is the order; the rows here are the phases' record.

## Done

| step | what | evidence |
|---|---|---|
| 1–3 (sessions 1–3) | the wiki, design v0, the grammar, 13 comparisons | `mo-wiki/` |
| 4 (session 5) | the corpus, 52 programs, three-model bake-off | [[corpus]], [[model-bakeoff]] |
| 5.1–5.4 (session 5) | lexer, parser, tier-1 checker, VM, tier-2 contracts, test runner, processes, supervisors, `Mo.Sim` scheduler: **the milestone** | [[interpreter-step-1]] … [[interpreter-step-4]], `08-milestone.md` |

## Step history (the overnight run of session 5 to step 33, every row done; newest first)

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
| later | the package registry ([[d34-packages-are-recipes]]); `mo prove` | deferred, see the phases table |

## Session 3 note

Robert: `spec/design-v0` is a folder of files, one per chapter. Kept.

## Related
- [[program-menu]]
- [[q14-first-real-program]]
- [[q13-implementation-language]]
- [[session-05]]
- [[decision-log]]
- [[comparison-pass]]
