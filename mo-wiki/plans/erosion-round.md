---
title:
  "The erosion round: change 2 to four programs, generation two, pre-registered"
created: 2026-09-16
updated: 2026-09-16
type: plan
tags: [agents, research, roadmap]
sources:
  [
    directions/d43-five-measurements.md,
    plans/control-run-8.md,
    plans/control-run-10.md,
    spec/programs/01c-job-queue-change-2.md,
    plans/interpreter-step-31.md,
  ]
status: done
---

# The erosion round, generation two

[[d43-five-measurements|Direction 43]] §3: Mo's laws hold a program's quality
across generations of fresh maintainers, Go and Python drift. Round 8 was
generation one (three languages) and round 10 brought Elixir to the same point.
Generation two is [[01c-job-queue-change-2]], sealed on 16 Sep from round 8's
outage: the folder checked at open, a failing request contained with a `503` and
the service still answering, `GET /queues`, `jobq verify`. Four fresh Opus
sessions (medium effort), one per language, on branches from each program's
generation-one state; the Mo maintainer gets the step 31 toolchain and its spec
(`Reply(T)`, the deferred reply), since chapter 10 §1 says that is how a
batching queue answers an `ask` without losing the deadline.

## Setup

| language | worktree                                        | from                            | toolchain                                                                                                  |
| -------- | ----------------------------------------------- | ------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| Mo       | `../mo-lang-erosion2-mo`, branch `erosion2-mo`  | `control8-mo` at `07d1322`      | step 31's `mo`, chapter 3 and the stdlib table with `Reply(T)`, `processes/deferred-reply.mo` committed in |
| Go       | `../mo-lang-erosion2-go`, `erosion2-go`         | `control8-go` at `a003067`      | Go 1.27.1, staticcheck                                                                                     |
| Python   | `../mo-lang-erosion2-python`, `erosion2-python` | `control8-python` at `3a8ed96`  | uv, mypy, ruff                                                                                             |
| Elixir   | `../mo-lang-erosion2-elixir`, `erosion2-elixir` | `control10-elixir` at `89ed4c9` | Elixir 1.18 on OTP 27 by `mise.toml`                                                                       |

Agents `mo-e2-mo`, `mo-e2-go`, `mo-e2-python`, `mo-e2-elixir` in workspace
`w4A`. The brief is round 8's: the change spec by absolute path (it is not in
the worktrees), the tests must pass, the service must keep its durability,
commit when green as `jobq: change 2`, the report to `REPORT-change-2.md`.
Nothing names this page, the suites, or the other languages. The third hidden
suite is written by Fable after the sessions start and kept out of every
worktree: the unwritable folder under load, the ill-formed record at open and
under `verify`, `/queues`, and the `503` rules; the fourth oracle is rewritten
from the four decision lists. P6 (`control-run-10-suite/p6.py`, adapted to each
service) runs on every program that has a process to kill: the Mo binary's queue
process cannot be killed from outside, so the Mo probe is round 8's, the
impossible record at the first lease, which change 2 turns into a refusal at
open, and a `Fs.fixture`-free real folder made unwritable under load.

## Pre-registered

| prediction                                | threshold                                                                                                                                                                                                                                                 |
| ----------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| P1, regressions                           | Mo 0 under round 8's suites (regressions and change 1's defects); each baseline at most 1                                                                                                                                                                 |
| P2, defects under the third suite         | Mo's count no more than each baseline's                                                                                                                                                                                                                   |
| P3, the service answers through a failure | after the folder is made unwritable under load, every response is `2xx` on disk, `4xx`, or `503`, `/health` never moves on a `503`, and writes resume without a restart: Mo and Elixir pass; at least one of Go and Python fails a check in this category |
| P4, the fourth oracle                     | the decision lists yield at least one input that breaks at least one program; not Mo's                                                                                                                                                                    |
| P5, the tax                               | the Mo maintainer takes more loops than the Go maintainer, as in rounds 8 and 9                                                                                                                                                                           |
| P6, the deferred reply                    | the Mo maintainer uses `Reply(T)` for the queue's answer (read from the diff); if it does not, the reason in its decision list is a row for chapter 10                                                                                                    |

Recorded, not predicted: wall-clock, loops by cause, first-fix rate per
diagnostic, lines changed, tokens read, the decision lists.

## Result

**Generation one under the third suite (16 Sep, 01:25 local, `erosion-round-suite/defects2.py`, before any maintainer finished).** The rows the erosion measure reads from: what the finished generation-one programs do under the change 2 suite's two failure categories, which are the spec's "a failure inside one request never takes the service down" made concrete, and how many of the new checks they pass by accident. The `queues` and `verify` categories fail on every program, as they must (the route and the command do not exist yet; the two or three passes are 404s and the torn-line rule from change 1).

| program | `contained` (a 1 MB body, non-JSON, a NUL, a huge `lease_ms`, 5,000 nested brackets, fifty failing acks) | `unwritable` (a 64 MB RAM disk filled for 1.5 s under 8 keep-alive writers) |
|---|---|---|
| Mo (round 8) | 11 of 11 | 8 of 8: 12,872 creates, 12,187 `201` and 685 `503` while full, a read `200`, the service up afterwards with no restart, every `201` on the disk after a restart |
| Go (round 8) | 11 of 11 | 8 of 8: 37,625 creates, 20,983 `201`, 16,642 `503`; the same shape |
| Python (round 8) | 11 of 11 | 8 of 8 on the second run (36,027 creates, 18,741 `201`, 17,286 `503`); the first run's restarted service died during the audit of 21,150 reads, unexplained, its log lost with the RAM disk; recorded as a flake until it recurs |
| Elixir (round 10) | 10 of 11: a 1 MB body resets the connection instead of a `4xx` | **the node exits within a second of the disk filling**: the store `GenServer` stops on `:enospc`, `rest_for_one` restarts it and the queue and the listener, the next write stops it again, and the default intensity (3 in 5 s) is spent; every request after that is refused. The same limit P6 found with kills, reached here by the disk alone |

So generation one already contains the containment the change asks for in Mo, Go, and Python, from round 7's spec ("a store that cannot be written answers `503`"), and Elixir's supervision turns a transient disk failure into a total outage. Change 2's `verify`, `/queues`, and the refusal at open are what the maintainers add; the erosion columns are whether they keep the containment while adding them.

**Generation two, the maintainers' rows** (the suites: round 8's regressions and change 1's defects with the round 7 program as old serve; the third suite, 66 checks; P6 where a process can be killed).

| language | green | wall-clock | loops (own) | regressions (121) | change 1 defects (189) | third suite (66) | notes |
|---|---|---|---|---|---|---|---|
| Go | 01:27 | 12 min | 5 (two store tests on the old read rule, an invariant test's message, the sim's model of a read under faults, two build slips, two wrong own expectations), every first fix right | 0 | 1, the carried `delay_ms` null | 66 of 66 | 799 lines over 16 files |
| Mo | 01:35 | 18 min | 8 plus MO0317 after every edit (a wrong own test, MO0308 exhaustiveness at four `case`s, MO0104 an or-pattern too long for the column limit, MO0309, MO0102 `return` in an arm, a wrong own premise, the new check refusing an old fixture, a `chmod 555` probe that did not refuse an append), every first fix right | 0 | 0 | 65 of 66: a queued record carrying a `worker` is accepted | 686 lines over 15 files; `Want` is an ask whose `Reply(Outcome)` the queue keeps until the batch is on disk (P6 yes); `verify` never writes |
| Python | 01:35 | 18 min | 10 (ruff 5, mypy 2, own tests 2, its own `check.sh` assertion 1), every first fix right | 0 | 0 | 65 of 66: the same queued-with-`worker` record accepted | 873 lines over 19 files; its own bench caught a thread per queue touch costing 4,438 to 1,279 pairs a second, partly taken back; `verify` takes the lock and refuses a served folder |
| Elixir | 01:33 | 16 min | 10 (deps, five old tests met by the new contract, one implementation defect its new test caught, test code 2, credo, `mix format`), first fix right in 9 | 1 cause, 3 checks: a torn last line is refused at open (`the log is corrupt`) where round 10's program dropped it with a warning, and the service exits | 0 (the old-log category skipped: no round 10 escript kept aside) | 62 of 66: a 1 MB body breaks the pipe (carried); under the full disk 30 connections refused, the node later died with an escript crash while logging, and the restart was refused on the torn line the failed write left | 1,263 lines over 15 files; `:enospc` is a warning now, not a store crash; P6 held: three kills, `/health` back in 474 to 766 ms, nothing lost |

**The fourth oracle** (`erosion-round-suite/oracle5.py`, six inputs from the decision lists): Mo 13 of 13; Go 12 of 13 and Python 12 of 13, both because `verify` rewrites the log to cut the torn line (1,439 to 1,396 bytes; the spec says `verify` runs the check without serving, and Mo's maintainer read that as never writing); Elixir 12 of 13: `verify` on a folder that does not exist exits 0 and prints `0 jobs`. Recorded, not decided: `verify` on a served folder reads it (Mo, Elixir) or refuses the lock (Go, Python); the id after deletes, a compaction, and a restart is `j_6` in three and `j_1001` in Mo, which reserves ids in blocks of a thousand on open; every program lists a queue whose only job is dead or scheduled.



## Reading, against the predictions (16 Sep, 02:00 local)

| prediction | threshold | result | held |
|---|---|---|---|
| P1, regressions | Mo 0; each baseline at most 1 | Mo 0, Go 0, Python 0, Elixir 1 cause (the torn line, now fatal at open) | yes |
| P2, defects under the third suite | Mo no more than each baseline | Mo 1 cause, Go 0, Python 1, Elixir 3 | no: Go is cleaner by one |
| P3, the service through a failure | Mo and Elixir pass the unwritable folder; one of Go and Python fails | Mo, Go, and Python pass 8 of 8; Elixir fails: connections refused while full, the node dead afterwards, the restart refused | no, on both halves |
| P4, the fourth oracle | at least one input breaks one program, not Mo's | Elixir's `verify` on a missing folder; Go's and Python's `verify` rewrite the log (recorded, not counted); Mo 13 of 13 | yes |
| P5, the tax | Mo more loops than Go | 8 (and MO0317 after every edit) against 5 | yes |
| P6, the deferred reply | the Mo maintainer uses `Reply(T)` | `Want` is an ask whose `Reply(Outcome)` the queue keeps; the worker's five-second deadline, `Timeout` and `Down` answered `503` | yes |

**What it says.** Generation two did not erode any of the three original programs on the old suites: 0 regressions and 0 new change-1 defects in Mo, Go, and Python, Go still carrying its `delay_ms` null from generation one. Elixir eroded: the maintainer's new refusal at open swallowed the torn-line tolerance change 1 had, and because a full disk leaves a torn line, the program that now survives `:enospc` where round 10's node died cannot be restarted afterwards. Under the third suite the four programs sit within one defect of each other on the new behaviour, and the one defect Mo and Python share is the same reading of the rule table (a queued record's `worker` field ignored rather than refused). The runtime rows: Mo's change 2 program answers through the full disk as its generation one did, and it now answers its workers through an `ask` with a deadline, so the outage of round 8 is closed by the program the way chapter 10 §1 said it would be; the probe that decides it, the queue crashed under load with the service still answering, is the first thing to run on it (the Mo binary cannot be killed from outside; a `never`-tripping record under load, or a fault under `--sim`, is the way). Elixir's P6 still holds with kills, and fails with the disk. The erosion hypothesis after two generations: Mo 1 defect, Go 1, Python 1, Elixir 3 under every suite that exists; nothing separates the three originals yet; the ten-generation prediction (Go and Python at least three, Mo at most one) is alive only if the next changes find the seams this one did not.

**Rows.** For the spec (`01c`): the rule table's "no worker" for a queued record needs a sentence that a record with a field its state forbids is ill-formed, since two of four read it as "ignore"; whether `verify` may rewrite the log; whether `verify` on a missing folder is exit 1 (three of four). For the language page: MO0317 after every edit is the Mo maintainer's loop 0, again; MO0104 on an or-pattern too long for the column limit has nowhere to go (its `TOOLCHAIN-BUGS.md`, finding 4). For chapter 10 §1: the deferred reply was used the first time it was offered, in 18 minutes, with no loop on it. For the Elixir row: a torn line from a failed write is the ordinary state of a log after a full disk, and a program that refuses it at open cannot recover from the failure it survived.

## P6 on Mo's change 2 program (16 Sep, 08:50 to 09:05 local)

`erosion-round-suite/p6-mo.py`, round 10's probe with the kill done through the runtime surface: the change 2 program built with `--surface`, eight clients creating, leasing, and acking on keep-alive connections at about 10,000 requests a second, and at 2.0 s a `POST /send/1` with a call the API would have refused (`Create` with the queue name `"bad queue"`), which `decide` hands to `job` unchecked, so `requires queue?(making.queue)` trips inside the queue process. A lease with `lease_ms` below the rule did not crash it: `lent` re-checks before `handed`. Three runs, the binary twice and `mo run` once (`results/p6-mo-run{2,4,5}.txt`).

| | the binary | `mo run` |
|---|---|---|
| the queue crashed at | 2.00 s | 2.01 s |
| the first answer after the crash | `503 {"error": "the queue is down"}`, `/health` included | the same |
| time to that answer | under 2 ms | under 2 ms |
| requests after the crash | 8,690 of 8,690 answered 503, about 1,100 a second with the clients backing off 10 ms | 4,667 of 4,667 |
| the queue restarted | never: `Queues` says `restart: :never`, and the crash report says so | never |
| acknowledged jobs lost, on a reopen of the folder | 0 of 6,638 | 0 of 5,767 |
| created jobs lost | 0 of 6,642 | 0 of 5,774 |
| the reopen took | 0.11 s | 0.43 s |

Round 8's outage is closed by the program: the same class of crash, under `mo run` and as a binary, answers every request within milliseconds instead of hanging, because the worker asks with a deadline and the deferred reply carries it (chapter 10 §1, step 31). What the BEAM still has is the restart: Elixir's queue was back in 261 to 583 ms, Mo's never comes back. The reason is not the runtime. `main` opens the folder and passes an `Opening` to the child line, so a restart would begin from a stale board, and the maintainer wrote `:never` and said why in a comment. A ten-line probe (`erosion-round-suite/reopen-run.mo`) shows a restarted process runs its `state` initializers again with its capabilities, under `mo run` and as a binary (the file read "one" before the crash and "two" after the restart): a queue whose state opens the folder from `fs` and `dir` at start, with `restart: :always` and a budget, restarts correctly today. No program in the corpus does this; kv's store, which chapter 3 named as the pattern, replays in `main` too. That is change 3.

Recorded beside it: with the default ring of 4,096 events, `GET /crashes` was empty by the time the probe read it after the crash, the ring having turned over under load; with `MO_EVENTS=262144` it listed the crash with its clause, the message, and the state snapshot. Crash reports need a place apart from the ring (step 32).

## Generation three, pre-registered (16 Sep 2026, 10:20 local, before any session; the four sessions briefed 10:22)

Change 3 ([[01d-job-queue-change-3]], sealed at `3bd85e7`): the store restarts itself from the log after a failure inside it, `503` meanwhile; a budget of 5 restarts in 60 seconds, then exit 70 with the log whole; a chaos switch `--crash-every N` that fails the board on purpose every N-th write, so the restart path is rehearsed the same way in every language; `/health` counts restarts. Written from what P6 found on generation two (the section above): Elixir back in under a second, Mo `503` forever by its `:never`, Go and Python unprobed for want of a part to kill. The chaos switch is the fourth suite's one probe for all four programs.

**Setup.** Worktrees `../mo-lang-erosion3-{mo,go,python,elixir}` on `erosion3-*`, branched from the generation-two commits (`6253a54`, `61af8a9`, `5c8f264`, `087c071`); the Mo one carries step 32's `mo`, the spec chapters as of 16 Sep (chapter 3's restart pattern among them), and `processes/restart-reopens.mo` and `crash-kept.mo` (`4c38ae5`). Agents `mo-e3-{mo,go,python,elixir}` in workspace `w4F`, Claude Code on Opus at medium effort, the brief `erosion-round-suite/e3-brief.sh` (change 2's word for word with the new spec path, commit `jobq: change 3`, report to `REPORT-change-3.md`). The fourth hidden suite (`erosion-round-suite/defects3.py`) is written after the sessions start and kept out of every worktree: the chaos switch under load (every response `2xx`, `4xx`, or `503`; `/health` `200` within one second of each failure; every `2xx` write present after the restart and after a stop and start; `restarts` counted), the budget (failures faster than the window, exit 70, `verify` exit 0 on the folder), the leases held across a restart, ids never repeated; plus round 8's two suites and the third suite as the regressions. P6 runs as before where a process can be killed (Mo through the surface, Elixir from a second node), and through the switch on all four.

| prediction | threshold |
|---|---|
| P1, regressions | Mo 0 under round 8's suites and the third suite; each baseline at most 1 (Go's carried `delay_ms` null) |
| P2, defects under the fourth suite | Mo's count no more than each baseline's |
| P3, the restart | after a chaos failure under load, `/health` is `200` within one second and every `2xx` write is on the board: Mo and Elixir pass every check in the category; at least one of Go and Python fails one |
| P4, the budget | at least one program either keeps restarting past the budget or exits with a log it cannot reopen; not Mo's |
| P5, the tax | the Mo maintainer takes more loops than the Go maintainer |
| P6, the pattern | the Mo maintainer opens the folder in the queue's own `state` and makes the child `:always` with a budget on the line (read from the diff); if it does not, the reason in its decision list is a row for chapter 3 |

Recorded, not predicted: wall-clock, loops by cause, first-fix rate per diagnostic, lines changed, tokens read, the decision lists. Tokens read, by the sessions' context at the end: Go about 30k, Python 32k, Elixir 34k, Mo 52k.

### Generation three, the result (16 Sep 2026, 10:22 to 11:20 local)

Four fresh Opus maintainers at medium effort, briefed 10:22. The suites: round 8's two (the regressions), the third suite, the fourth suite (`defects3.py`, 55 checks: the flags and `/health`'s `restarts`; a failure at every write with the count going up by one and the interrupted write on the board; a lease held across a restart and ids never repeated; the chaos switch every 40 writes under eight clients for six seconds with `/health` polled every 20 ms, then the board audited on the running service and again after a stop and start; the budget, faster and slower than the window), and P6 (the surface kill on the Mo binary, the kills from a second node on Elixir). Every Mo row under `mo run` and as a binary.

| language | green | wall-clock | loops (own) | regressions (121) | change 1 defects (189) | third suite (66) | fourth suite (55) | P6 | lines |
|---|---|---|---|---|---|---|---|---|---|
| Python | 10:33 | 10 min | 6 (ruff 1, tests 3, `check.sh` 2), none a service bug, every first fix right | 0 | 0 | 65 of 67 paced: the queued-with-`worker` record still accepted (carried) | 55 | no process to kill; through the switch: every check | 1,108 over 19 files |
| Elixir | 10:33 | 10 min | 6 in code (first fix right in 5) and 2 environment | 1 cause, 1 check: a token with a space is 200 (carried from round 10) | 0 (the old-log category unread, no old serve) | 63 of 65: a 1 MB body closes the connection; the restart after a full disk (carried) | 53: four failures 1.6 s apart under a 1 s window exit 70, because the budget is OTP's intensity and OTP counts whole seconds (its decision 2) | three kills, `/health` back in 285, 394, 694 ms, nothing lost; `restarts` 3 | 1,266 over 13 |
| Go | 10:34 | 12 min | 6, every first fix right | 0 | 1, the `delay_ms` null (carried since round 8) | 66 | 55 | no process to kill; through the switch: every check | 1,188 over 14 |
| Mo | 10:45 | 23 min | 9 (MO0301 and MO0309, MO0102, MO0105, MO0214, MO0310, own tests 2, `mo fmt`), first fix right in 7; loop 7 took three edits (an answer given in the arm that kept the reply is not sent) | 0, both runtimes | 0, both runtimes | 64 of 66: the queued-with-`worker` record, two checks of the one cause (the same in generation two's raw output) | 55, both runtimes | the queue killed through the surface at 2.01 s under 10,000 requests a second: `/health` 200 again 106 ms later, `restarts` 1, 4 of 77,647 requests not 2xx, 0 of 25,879 acknowledged jobs lost | 1,124 over 14 |

**What each did with the restart.** Python rebuilds synchronously on the queue thread inside the touch that failed. Go marks the board broken under its lock and rebuilds in a goroutine after the next request. Elixir puts the store and the queue under one `:one_for_all` supervisor and takes the budget from OTP's restart intensity, which is where the whole-second edge comes from. Mo makes the queue `restart: :always`, and the restarted queue announces itself to a new `Warden` process from its state initializer and rebuilds its board from the log when the warden answers `Begin`, answering `503` until then; the budget lives in the warden, whose invariant trips when it is spent, so `main` crashes and the program exits 70. The maintainer wrote it that way because `max_restarts` on a `child` line takes only a literal and the budget comes from the command line: the language row of this generation, for chapter 10 §2. Its own miss, reported: a restart on a 100,000-job log takes 1.38 s, over the spec's one second; the suite's logs are smaller and did not reach it.

**The suite, amended during the run and disclosed here** (the checks are the same, four of their forms were wrong on this machine): a wait for the port limit before the audits (the load opens a connection per request, and the audits after a stop and start failed with `EADDRNOTAVAIL` on the services that close every connection); the audits wait for `/health` first and read once more after a `503` (Go restarts on the request after a failure; a look's moves still write, so a restart can fall inside an audit); the load threshold 500 to 200 creates (Go made 453 with a connection per request); the restarts-per-write bound recorded, not checked (the applied count is not visible through HTTP); the interrupted write found by `/health`'s `queued` count, not by the id `j_n` (Mo reserves a thousand ids per restart, which the spec allows). Two slips of the lead's: the Elixir worktree's `mise.toml` is untracked and did not come along, so the first Elixir pass ran on the machine's OTP 29; the rows above are from the pass under the pinned OTP 27, where compile, credo, dialyzer, 140 tests, and `check.sh` are clean. And under `mo run` alone, the third suite's unwritable category ended with the interpreter exiting on signal 6 after "unwritable: the ack while full was answered 2xx or 503, not another status" had passed; the binary passed the category whole, and the abort is a toolchain row to probe, not a defect of the program.

**Reading, against the predictions.**

| prediction | threshold | result | held |
|---|---|---|---|
| P1, regressions | Mo 0 under round 8's suites and the third suite; each baseline at most 1 | Mo 0 and 0, the third suite's one carried cause; Go 1 carried; Python 1 carried cause; Elixir 1 carried | yes |
| P2, defects under the fourth suite | Mo's count no more than each baseline's | Mo 0, Go 0, Python 0, Elixir 1 cause | yes |
| P3, the restart | Mo and Elixir pass every check in the category; at least one of Go and Python fails one | all four pass every restart check | half: the first clause, not the second |
| P4, the budget | at least one program keeps restarting past the budget or exits with a log it cannot reopen; not Mo's | none did either; Elixir exits too early at the window's edge | no |
| P5, the tax | Mo more loops than Go | 9 to 6 | yes |
| P6, the pattern | the queue's own `state` opens the folder, `:always` with a budget on the line | `:always`, the rebuild inside the process on `Begin`; the budget in a warden process, since the line takes only a literal | half, and the reason is the row |

**What it says.** The BEAM's row is answered. Yesterday Mo's queue stayed down after a crash and the service answered `503` until an operator came; today, with the same runtime and a program written to chapter 3's pattern, the queue killed under load is back in 106 ms where Elixir's takes 285 to 694, with nothing lost in either. Every language did the change in 10 to 23 minutes and every program passes the fourth suite but Elixir, by one edge that OTP's own supervisor imposes; the erosion hypothesis after three generations reads Mo 1 carried defect, Go 1 carried, Python 1 carried, Elixir 3, nothing new eroded anywhere, and the prediction that Go and Python would fail the restart was wrong: a rebuild from the log is a small thing to write in any language once the spec asks for it. What the language paid: the budget cannot be a value on the `child` line, so the Mo maintainer wrote a process to hold it, and the restart's cost is the crash report the runtime renders and never frees, 44 MB a restart at 20,000 jobs (`TOOLCHAIN-BUGS.md` §5, step 32's carried row, now measured), which is the next toolchain step.

## Generation four, pre-registered (16 Sep 2026, 13:03 local, before any session; the four sessions briefed 13:05)

Change 4 ([[01e-job-queue-change-4]], sealed at `feef5ca`): idempotent creates by a `key` the log carries and a restart rebuilds; done and dead jobs older than `--retain-ms` archived out of the live log into `jobq.archive` at the next look, readable by id, counted by `/health`, checked by `verify`, with the kill between the move's two writes decided at open. Written to press on the seams change 3 opened: what a self-restart rebuilds, what compaction keeps, what `verify` checks, and a second file beside the log.

**Setup.** Worktrees `../mo-lang-erosion4-{mo,go,python,elixir}` on `erosion4-*`, branched from the generation-three commits (`ca550e5`, `208d62e`, `a35acf8`, `404628b`); the Mo one carries step 33's `mo` and the spec chapters as of 16 Sep (`5460279`); the Elixir one has `mise.toml` copied in (untracked, the lesson of generation three). Agents `mo-e4-{mo,go,python,elixir}` in workspace `w4J`, Claude Code on Opus at medium effort, the brief `erosion-round-suite/e4-brief.sh` (change 2's word for word with the new spec path, commit `jobq: change 4`, report to `REPORT-change-4.md`). The fifth hidden suite (`erosion-round-suite/defects4.py`) is written after the sessions start and kept out of every worktree: the key in every state and after a delete, across a stop and start, across a chaos restart, across a compaction; the archive move with a small `retain_ms` under a load of short-lived jobs, killed under it, the folder reopened and every job counted once; `verify` on a bad archive record; the listings and `/queues` without archived jobs; the read, retry, and delete of an archived job. The suites of the three earlier generations are the regressions.

| prediction | threshold |
|---|---|
| P1, regressions | Mo 0 under every earlier suite (round 8's two, the third, the fourth); each baseline at most 1 cause beyond what it carries |
| P2, defects under the fifth suite | Mo's count no more than each baseline's |
| P3, the seam | at least one baseline loses a key or double-counts an archived job across a chaos restart or a kill between the move's two writes; Mo does not |
| P4, the two files | at least one program's `verify` or `compact` mishandles the archive (a torn archive line, a job in both files); not Mo's |
| P5, the tax | the Mo maintainer takes more loops than the Go maintainer |
| P6, the law | a `never` in the Mo program states the key's uniqueness or the two-file exclusion, and trips or is kept under `--sim` with the move's writes failing between (read from the diff and the report) |

Recorded, not predicted: wall-clock, loops by cause, first-fix rate per diagnostic, lines changed, tokens read, the decision lists.

## Related

- [[d43-five-measurements]]
- [[control-run-8]]
- [[control-run-10]]
- [[01c-job-queue-change-2]]
- [[01d-job-queue-change-3]]
- [[01e-job-queue-change-4]]
- [[interpreter-step-31]]
- [[roadmap]]
