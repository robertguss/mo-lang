---
title:
  "The erosion round: changes 2 to 5 to four programs, generations two to five"
created: 2026-09-16
updated: 2026-09-18
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
status: in-progress
---

# The erosion round, generations two to six (generation six run and read, 18 Sep)

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
| Elixir (round 10) | 10 of 11: a 1 MB body resets the connection instead of a `4xx` | **the node exits within a second of the disk filling**: the store `GenServer` stops on `:enospc`, `rest_for_one` restarts it and the queue and the listener, the next write stops it again, and Elixir `Supervisor`'s default intensity (3 in 5 s; Erlang's own default is 1 in 5 s) is spent; every request after that is refused. The same limit P6 found with kills, reached here by the disk alone |

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

Recorded beside it: with the default ring of 4,096 events, `GET /crashes` was empty by the time the probe read it after the crash, the ring having turned over under load; with `MO_EVENTS=262144` it listed the crash with its clause, the message, and the state snapshot. Crash reports need a place apart from the ring ([[interpreter-step-32]]).

## Generation three, pre-registered (16 Sep 2026, 10:20 local, before any session; the four sessions briefed 10:22)

Change 3 ([[01d-job-queue-change-3]], sealed at `3bd85e7`): the store restarts itself from the log after a failure inside it, `503` meanwhile; a budget of 5 restarts in 60 seconds, then exit 70 with the log whole; a chaos switch `--crash-every N` that fails the board on purpose every N-th write, so the restart path is rehearsed the same way in every language; `/health` counts restarts. Written from what P6 found on generation two (the section above): Elixir back in under a second, Mo `503` forever by its `:never`, Go and Python unprobed for want of a part to kill. The chaos switch is the fourth suite's one probe for all four programs.

**Setup.** Worktrees `../mo-lang-erosion3-{mo,go,python,elixir}` on `erosion3-*`, branched from the generation-two commits (`6253a54`, `61af8a9`, `5c8f264`, `087c071`); the Mo one carries [[interpreter-step-32]]'s `mo`, the spec chapters as of 16 Sep (chapter 3's restart pattern among them), and `processes/restart-reopens.mo` and `crash-kept.mo` (`4c38ae5`). Agents `mo-e3-{mo,go,python,elixir}` in workspace `w4F`, Claude Code on Opus at medium effort, the brief `erosion-round-suite/e3-brief.sh` (change 2's word for word with the new spec path, commit `jobq: change 3`, report to `REPORT-change-3.md`). The fourth hidden suite (`erosion-round-suite/defects3.py`) is written after the sessions start and kept out of every worktree: the chaos switch under load (every response `2xx`, `4xx`, or `503`; `/health` `200` within one second of each failure; every `2xx` write present after the restart and after a stop and start; `restarts` counted), the budget (failures faster than the window, exit 70, `verify` exit 0 on the folder), the leases held across a restart, ids never repeated; plus round 8's two suites and the third suite as the regressions. P6 runs as before where a process can be killed (Mo through the surface, Elixir from a second node), and through the switch on all four.

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

**Setup.** Worktrees `../mo-lang-erosion4-{mo,go,python,elixir}` on `erosion4-*`, branched from the generation-three commits (`ca550e5`, `208d62e`, `a35acf8`, `404628b`); the Mo one carries [[interpreter-step-33]]'s `mo` and the spec chapters as of 16 Sep (`5460279`); the Elixir one has `mise.toml` copied in (untracked, the lesson of generation three). Agents `mo-e4-{mo,go,python,elixir}` in workspace `w4J`, Claude Code on Opus at medium effort, the brief `erosion-round-suite/e4-brief.sh` (change 2's word for word with the new spec path, commit `jobq: change 4`, report to `REPORT-change-4.md`). The fifth hidden suite (`erosion-round-suite/defects4.py`) is written after the sessions start and kept out of every worktree: the key in every state and after a delete, across a stop and start, across a chaos restart, across a compaction; the archive move with a small `retain_ms` under a load of short-lived jobs, killed under it, the folder reopened and every job counted once; `verify` on a bad archive record; the listings and `/queues` without archived jobs; the read, retry, and delete of an archived job. The suites of the three earlier generations are the regressions.

| prediction | threshold |
|---|---|
| P1, regressions | Mo 0 under every earlier suite (round 8's two, the third, the fourth); each baseline at most 1 cause beyond what it carries |
| P2, defects under the fifth suite | Mo's count no more than each baseline's |
| P3, the seam | at least one baseline loses a key or double-counts an archived job across a chaos restart or a kill between the move's two writes; Mo does not |
| P4, the two files | at least one program's `verify` or `compact` mishandles the archive (a torn archive line, a job in both files); not Mo's |
| P5, the tax | the Mo maintainer takes more loops than the Go maintainer |
| P6, the law | a `never` in the Mo program states the key's uniqueness or the two-file exclusion, and trips or is kept under `--sim` with the move's writes failing between (read from the diff and the report) |

Recorded, not predicted: wall-clock, loops by cause, first-fix rate per diagnostic, lines changed, tokens read, the decision lists.

### Generation four, the result (16 Sep 2026, 13:05 to 15:05 local)

Four fresh Opus maintainers at medium effort, briefed 13:05. The Mac slept several times between 13:10 and 14:10 and cut every session short at least once; each was prompted to continue, and the machine was held awake from 14:13. So the wall-clock column below is every session's own figure, 77 to 89 minutes, and every one includes the sleeps: this generation has no honest time column, and the earlier generations' 10 to 23 minutes stand as the measure of the change's size (generation four's change is larger, about 1,400 to 2,000 lines against generation three's 1,100 to 1,300). The suites: the four earlier ones as regressions and the fifth (`defects4.py`, 77 checks: the flags; the key's rule, the second create answered with the first job in every state including archived, the key freed by a delete, the lookup; the key kept across a chaos restart, a stop and start, a compaction; the archive after `retain_ms` in `/health`, the listings, `/queues`, the read, retry, delete, `verify`'s line, the file; the archive under a kill with short-lived jobs and `retain_ms` of one second, every job counted once on the reopened folder, keys of archived jobs still used; a bad archive record refusing the folder and a torn archive line cut), P6 as in generation three. Every Mo row under `mo run` and as a binary.

| language | green | loops (own) | regressions (121) | change 1 (189) | third suite (66) | fourth (55) | fifth (77) | P6 | lines |
|---|---|---|---|---|---|---|---|---|---|
| Python | 14:23 | 11 (ruff 1, expected output 4, own tests 3, `check.sh` 2, sim 1), first fix right in every one | 0 | 0 | 65: the queued-with-`worker` record (carried) | 55 | 77 | through the switch: every check | 1,358 over 15 files |
| Elixir | 14:25 | 7 after a baseline timing failure it did not edit, first fix right in every one | 1 cause: a token with a space is 200 (carried from round 10) | 0 (the old-log category unread) | 63 of 65: a 1 MB body closes the connection; the restart after a full disk (both carried) | 53: the budget at the window's edge (carried) | 76: a repeated `--retain-ms` accepted | three kills, `/health` back in 324, 594, 876 ms, nothing lost | 1,609 over 19 |
| Go | 14:25 | 6, every first fix right | 0 | 1, the `delay_ms` null (carried since round 8) | 66 | 55 | 76: `"key": null` read as no key, where the spec's letter is 400 (its decision 2; a reading) | through the switch: every check | 1,808 over 19 |
| Mo | 14:35 | 11 (MO0317 twice as process slips, MO0105 twice, MO0214 and MO0314, MO0212, MO0102, own tests 3, `--sim` 1), first fix right in 10 | 0, both runtimes | 0, both runtimes | 64: the queued-with-`worker` record, two checks of the carried cause, both runtimes | 55, both runtimes | 77 as a binary; 77 under `mo run` in three runs of three after one run counted 2,634 of 2,635 created jobs on the reopened folder (recorded as a flake until it recurs) | the queue killed through the surface twice under load: `/health` 200 again 58 and 85 ms later, 6 of 18,969 requests not 2xx, nothing lost | 1,956 over 14 |

Tokens read, by the sessions' context at the end: Python about 36k, Go 42k, Elixir 44k, Mo 62k.

**What each did with the archive.** All four archive at the look, record the move in the live log, and let the archive win at open when a job is in both files; all four count `archived` as undeleted archived jobs, not lines; three of four (Go, Python, Mo) answer a key lookup with an archived job, Elixir hides it ("listings never show archived jobs" read over "answers that job"). Mo writes the archive's lines before the live log's in every batch, keeps a deleted archived job as an archive tombstone `SET j_N deleted` until compaction, and keeps archived jobs in memory, paged like the live ones, so the log stops growing and memory does not shrink: a row for the spec (change 5 may ask for archived jobs read from the disk). Mo's maintainer wrote the `never` the pre-registration asked for: "a job is on the live board and in the archive at once after an open". Its switch counts the ids reservation as a record, which the first form of the suite's restart check tripped on.

**The suites, amended during the run and disclosed here** (the checks are the same): the third suite's `verify` counts-line check now accepts the "; archived <a>" ending change 4 adds (every program failed it the same way); the fifth suite's key-kept category induces the chaos restart by plain creates until one fails instead of a fixed write number (the programs count records differently); the archive-under-kill category counts one id per archive line (Mo's line names the id twice) and compares totals across two reopens (done jobs age into the archive between them); `verify` runs on an unserved folder (Go's refuses a served one). The lead's slips: Go's change 1 suite ran with wrong arguments the first time and was rerun (188 of 189, the carried null); the Mo P6 message had to gain `key: None` once `Making` had the field.

**Reading, against the predictions.**

| prediction | threshold | result | held |
|---|---|---|---|
| P1, regressions | Mo 0 under every earlier suite; each baseline at most 1 cause beyond what it carries | Mo 0 new (its carried cause only); Go, Python, Elixir nothing new | yes |
| P2, defects under the fifth suite | Mo's count no more than each baseline's | Mo 0 causes, Python 0, Go 1 (a reading), Elixir 1 | yes |
| P3, the seam | a baseline loses a key or double-counts an archived job across a chaos restart or the kill; Mo does not | none did | no |
| P4, the two files | a program's `verify` or `compact` mishandles the archive; not Mo's | none did | no |
| P5, the tax | Mo more loops than Go | 11 to 6 | yes |
| P6, the law | a `never` states the key's uniqueness or the two-file exclusion | the two-file exclusion, as a `never` in `board.mo` | yes |

**What it says.** The seam did not open. A key the log carries and an archive beside the log, written across a self-restart, a kill between two writes, and a compaction, came out whole in all four languages, from four fresh maintainers who had never seen the programs; the fifth suite's two misses are a reading of `null` and a repeated flag. After four generations the erosion hypothesis reads Mo 1 carried defect, Go 1 carried, Python 1 carried, Elixir 3 carried, and nothing new in any of them since generation one; the ten-generation prediction (Go and Python at least three, Mo at most one) is alive only in its Mo half. What the language paid this time was the tax again, 11 loops to Go's 6, two of them the maintainer's own `--write` slips; what it gave was the one `never` that states the rule the change is about, which no baseline has a place for. The next change has to find a seam the specs so far have not: the archive read from the disk, or a change that cuts across the queue's own invariants.

## Generation five, pre-registered (16 Sep 2026, 17:05 local, before any session)

Change 5 ([[01f-job-queue-change-5]], sealed at `897be13`): a leased job handed to another worker by name, the lease and its `tries` unchanged, the old worker `409` from then on; a queue renamed with jobs in flight in every state, live or archived, keys included, leases untouched, as one durable record the replay applies in order, `compact` folds, and `verify` checks. Written to press on the queue's own rules rather than on durability: two `never`s from the first day ("a job is never held by two workers at once"; "one record per job under its id") stand in the way of the two features, and the maintainer has to change the rule without breaking what it protected. This is the first change whose seam is a law, and so the first that can show a `never` catching a change-induced bug, the row the whole project turns on.

**Setup.** Worktrees `../mo-lang-erosion5-{mo,go,python,elixir}` on `erosion5-*`, branched from the generation-four commits (`3625392`, `af977ce`, `b75266c`, `2c247ad`); the Mo one carries step 34's `mo` if step 34 is accepted before the sessions start, step 33's otherwise (the result says which), and the spec chapters as of 16 Sep; the Elixir one has `mise.toml` copied in. Agents `mo-e5-{mo,go,python,elixir}` in a workspace of their own, closed when the sessions end, Claude Code on Opus at medium effort, the brief `erosion-round-suite/e5-brief.sh` (change 4's word for word with the new spec path, commit `jobq: change 5`, report to `REPORT-change-5.md`). The sessions start after step 34's measurement is off the machine, so neither loads the other; `caffeinate` held. The sixth hidden suite (`erosion-round-suite/defects5.py`) is written after the sessions start and kept out of every worktree: the handoff from the holder, a stranger, after expiry, to oneself, in a chain, across a stop and start and a chaos restart; the old worker's ack `409` and the new one's `200`; the rename with jobs in every state and with keys, the lease in flight acked after, `404` on an empty name, `409` on an existing target and on the same name, the listings and `/queues` and the key lookup after, the rename back, a fresh queue under the old name; the rename record in the replay's order (a job created into the old name after the rename), `compact` with two renames and the archive under an old name, `verify` on a bad rename record; and under load (leases, acks, keyed creates, handoffs) a rename, a kill during it, the folder reopened, every job in exactly one queue, every key once per queue, every acknowledged write present, no job with two workers. The five earlier suites are the regressions; P6 as in generation three.

| prediction | threshold |
|---|---|
| P1, regressions | Mo 0 under every earlier suite (round 8's two, the third, fourth, and fifth); each baseline at most 1 cause beyond what it carries |
| P2, defects under the sixth suite | Mo's count no more than each baseline's |
| P3, the seam | at least one baseline breaks a rule the earlier suites held, under the handoff or the rename with a kill: a job with two workers, a job in two queues or none, a key twice in a queue, a lease changed by a rename; Mo does not |
| P4, the record | at least one program replays the rename out of order, or `compact` or `verify` mishandles the rename record or the archive's old name; not Mo's |
| P5, the tax | the Mo maintainer takes more loops than the Go maintainer |
| P6, the law | the Mo maintainer changes or adds a `never` or `invariant` for the handoff or the rename, and at least one trips during the work on an edit that was wrong (the report or the loop log says so): the first change-induced bug a law catches |

Recorded, not predicted: wall-clock (the machine held awake, so this generation has one), loops by cause, first-fix rate per diagnostic, lines changed, tokens read, the decision lists, and which `never` each Mo edit touched.

**Started** 21:18 local, after [[interpreter-step-34]]'s acceptance: the Mo worktree carries step 34's `mo` and the spec chapters as of step 34 (`b7203c1`); agents `mo-e5-{mo,go,python,elixir}` in workspace `w4M`. The sixth suite, `defects5.py`, written 21:20 to 21:40 (91 checks over five categories; on the change 4 Mo program 26 pass and 65 fail on the missing routes, the harness running to its end). **Added to the record before any result** (from Fable's step 34 probe, in the decision log): pairs and creates a second at 32 workers, 1 core, for every program of this generation against its generation-four program, the round's speed column applied per generation from now on; the three baselines' generation-four rows are being measured while the sessions read their briefs (fsync-bound rows, the overlap noted).

### Generation five, the result (16 Sep 2026, 21:18 to 22:55 local)

> **Correction, 18 Sep 2026, 10:28 AM ET.** The "third (66)" column below was **not run** in generation five: the runner called `defects2.py` without `--log-format`, the suite exited 2 with a usage error for every program (`erosion-round-suite/results/e5-*-defects2.txt`), and the runner discarded the status. The numbers in that column are generation four's, carried without being measured. They are left in place and struck by this note; the measured numbers are added below when the rerun is done (the decision-log row of 18 Sep).

Four fresh Opus maintainers at medium effort, briefed 21:18, the machine held awake; every session's own wall-clock is honest this time. The suites: round 8's two (the regressions), the third, fourth, and fifth suites, and the sixth (`defects5.py`, 94 checks: the handoff from the holder, a stranger, after expiry, to oneself, in a chain, on a job not leased, with a bad `to`, on an unknown job, the old worker `409` and the new one `200` after; the handoff across a stop and start, a compaction, and a chaos restart; the rename with jobs in every state and keys, the lease in flight acked after, the listings, `/queues`, the key lookup, a fresh queue under the old name, `404`, `409`, `400`; the rename record in the replay's order, `compact` with two renames and the archive under an old name, `verify` on a bad rename record; a rename under a load of keyed creates, leases, acks, and handoffs with the service killed as it lands). P6 as in generation three. Every Mo row under `mo run` and as a binary.

| language | wall-clock | loops (own) | regressions (121) | change 1 (189) | third (66) | fourth (55) | fifth (80) | sixth (94) | P6 | lines |
|---|---|---|---|---|---|---|---|---|---|---|
| Elixir | 11 min | 5 (deps, credo, a shell slip, a port held after `kill -9`, two CLI tests asserting the script's counts), first fix right in every one | 120: a token with a space is 200 (carried) | the old-log category unread (carried) | 63 of 65: the 1 MB body, the restart after a full disk (carried) | 53: the budget at the window's edge (carried) | 79: a repeated flag accepted (carried) | 94 | three kills, `/health` back in 279, 491, 856 ms, nothing lost | 1,477 over 14 files |
| Go | 14 min | 2 test mistakes and 1 coverage gap, first fix right in every one | 121 | 188: the `delay_ms` null (carried) | 66 | 55 | 78: `"key": null` read as no key (carried); one create durable but unanswered under the kill, counted once more than the client saw (the check's tolerance, not a defect) | 92: `to` accepted at 256 bytes where the spec says 128 (a reading, 2 checks, 1 cause) | through the switch: every check | 1,729 over 12 |
| Python | 15 min | 13 (an invocation, a fixture's age, lint twice, old tests meeting the new rules, test bugs, sim bugs twice, coverage floors twice, the transcript, a `check.sh` slip, a harness bug), first fix right in every one | 121 | 189 | 65: the queued-with-`worker` record (carried) | 55 | 80 | 94 | through the switch: every check | 1,501 over 11 |
| Mo | 25 min | 14 (MO0105 three times, MO0501, MO0301, MO0303, MO0304 twice, MO0411, MO0317 three times as process slips, `mo fmt`, four test bugs), first fix right in 13 | 121, both runtimes | 189, both runtimes | 66, both runtimes | 55, both runtimes | 80, both runtimes | **93: after a compaction, one more rename, and a stop, the folder refuses to open** (`verify` and `serve` exit 1: "the rename count is below rename_3"; the compaction keeps a `SET renames n` record that a later rename never raises; both runtimes; reproduced by hand) | the queue killed through the surface twice under load: `/health` 200 again 55 and 99 ms later, 0 acked jobs not done, 0 created jobs gone, 7,130 done on the reopened folder | 1,838 over 11 |

Tokens read, by the sessions' context at the end: Go and Python about 42k each (79 percent of the window left); Mo's and Elixir's panes no longer showed the line when read.

**Speed, the row added this generation** (`control-run-8-suite/measure.py`, 100,000 creates then lease-and-ack pairs a second at 1 and 32 workers, `MO_CORES=1`, one run each, on a quiet machine after every suite):

| program | round 7 / change 1 / change 2 / change 3 (pairs at 32) | change 4 (creates; pairs at 1 / 32) | change 5 (creates; pairs at 1 / 32; restart) |
|---|---|---|---|
| Mo, binary, this step's `mo` | 4,040 / 4,045 / 4,142 / 4,068 (about 2,000 at 1 worker) | 8,300; 730 / 452 | 8,182; 725 / 425; 2.22 s on a 39 MB log |
| Go | — | 203; 56 / 104 | 202; 52 / 107; 0.30 s on 32 MB (one fsync a write on this disk; its 100,000 creates took 495 s) |
| Python | — | 10,071; 2,218 / 4,834 | 10,189; 2,280 / 4,847; 1.62 s on 90 MB |
| Elixir | — | 10,201; 1,725 / 5,624 | 9,729; 1,376 / 5,619; 4.78 s on 64 MB |

The Mo rows before change 5 are the step 34 probe's (two runs each, [[interpreter-step-34]]); the baselines' change 3 rows: Go 202 creates a second and 87 / 65 pairs at 1 / 32 workers; Python 10,987 and 2,465 / 4,911; Elixir 10,168 and 1,670 / 5,752. Change 5 cost no program its speed. Mo's lease path stays where change 4 left it, nine times below the program it was handed at 32 workers and 2.7 below at one; its creates are the fastest of the four and its restart the second slowest. Python and Elixir batch their fsyncs and are ten to forty times Go on this disk; Go fsyncs every write.

**The cause of the nine times, named (17 Sep 2026, on the VM).** Not the runtime and not the key map: change 4's `sweep` gained `ensures all_ends(result.board).all?(fn(e) !old_enough?(board, e.1, now) end)`, a postcondition over every finished job, and `decide` runs `sweep` on every request, so each lease and ack walks the whole archive-to-be. At 30,000 jobs on the VM, pairs at 32 workers: generation three 1,664, generation four 533; with `MO_CONTRACTS=0`, 1,793 and 1,736. `perf` shows 23 percent of the server in that one anonymous function. The row stays as measured, contracts on, because that is what ships; the diagnostic that would have shown it is a chapter 10 candidate (the [[decision-log]] row of 17 Sep, 19:25 UTC).

**What each did with the laws.** Go and Elixir both changed the log checker's "a job is never held by two workers at once" *before* writing the handoff (Mo kept its `never` of that sentence unchanged, and it did not trip) (a leased record after a leased record is allowed only in the handoff's shape: the worker changed, `tries` and `lease_until` the same), so it never tripped; Go added "a job never changes queue but by a rename" and "a rename never lets a key name two jobs"; Elixir added the rename record's rules to the folder check at open. Python's sim gained "only the holder hands a lease off" and "a rename changes nothing but the queue", both of which tripped on the maintainer's own sim code twice (loops 6 and 7), not on the program. Mo kept "a job is held by two workers at once" unchanged (a handoff replaces the one `worker`), added three `never`s ("a handoff changes a lease's `lease_until` or a job's `tries`, or leaves the job with no worker"; "a rename leaves a job in no queue but its own or the new one, or moves a job of another queue"; "a rename touches a lease") with `requires` and `ensures` on both steps, and reports that none tripped except where a `test rejects` means them to; its one real bug during the work (a rename and an archive move sharing a batch) was found by reading, and the one it shipped (the count after a compaction) is refused by its own open-time rule.

**What all four found in the spec.** The sentence "an archived job's queue is the live log's renames applied to the archive record's queue" is wrong once a name is reused: a job created into `a` after `a` was renamed to `b`, then archived, would be moved to `b` at the next open. Every maintainer saw it and fixed it with a position: Go a `next_id` on the rename record, Python and Mo a rename count on every record written after the first rename, Elixir the log's own name while the log still names the job. The next revision of the spec says it that way. Three of four also disagreed with the spec's 128-byte `to` against their programs' 256-byte tokens (Go kept 256, the sixth suite's one Go miss), and all four read "unchanged apart from `updated_at`" as "`updated_at` changes", which is what the sentence should have said.

**The suites, amended during the run and disclosed here** (the checks are the same; the check counts on this page differ between a suite's writing and its result table where a suite was amended: the sixth 91 as written to 94, the fifth 77 in generation four's table to 80 in generation five's, the third's Python cell 65 of 67 under a heading of 66; the result tables carry the count the suite had when it ran): the sixth suite's rename setup leased the wrong job three times over (a lease hands out the oldest queued job, so the job meant to be leased, acked, or archived must be created while nothing else is queued; 21:58 and 22:12), its live listing after the archive move expected 5, then 4, and is 3 (done and dead jobs both age into the archive; 22:24), its leased count after the handoff category expected 2 and is 1 (21:58), and its kill category kept creating into the old name after the rename (a fresh queue under it is by the spec) and counted a create durable but unanswered as a defect (21:58); every program failed each of these the same way and passed once amended. Elixir's regressions were rerun alone after three categories died on the Mac's port exhaustion (`errno 49`) right behind Python's suite. The lead's slips: P6 on Mo ran first against a binary built without `--surface` (a traceback, rerun on the right binary); the first two attempts at the baselines' speed rows died on the lead's own harness (a buffered pipe under a timeout, then the sixth suite's smoke run killing every server under the temp folder), so those rows were measured last, alone.

**Reading, against the predictions.**

| prediction | threshold | result | held |
|---|---|---|---|
| P1, regressions | Mo 0 under every earlier suite; each baseline at most 1 cause beyond what it carries | Mo 0 new, both runtimes; Go, Python, Elixir nothing new | yes |
| P2, defects under the sixth suite | Mo's count no more than each baseline's | Mo 1 cause (the count after a compaction: the folder refuses to open), Go 1 (a reading of the `to` rule), Python 0, Elixir 0 | **no**: the first generation in which Mo carries a defect a baseline does not |
| P3, the seam | a baseline breaks a rule under the handoff or the rename with a kill; Mo does not | none did: every program kept one worker, one queue, one key, the lease untouched, under the kill | no |
| P4, the record | a program's replay, `compact`, or `verify` mishandles the rename record or the archive's old name; not Mo's | only Mo's: `compact` leaves a count a later rename does not raise, and `verify` then refuses the folder the service wrote | **no**, the wrong way round |
| P5, the tax | Mo more loops than Go | 14 to 3 | yes |
| P6, the law | the Mo maintainer changes or adds a `never` or `invariant`, and one trips on a wrong edit during the work | three `never`s added, none tripped on a wrong edit; the bug during the work was found by reading; the shipped bug is refused at open by the program's own rule, after the fact | no |

**What it says.** The seam was a law, and the law did not earn its row: the Mo maintainer wrote three `never`s for the change and none caught the two bugs it made, one found by reading and one shipped. What the shipped bug shows is the other half of the language's bet, and it cuts both ways. Mo's change 5 program is the only one of the four that can write a folder it will not reopen, because it is the only one whose `compact` keeps a count beside the records it folds; but it is also the only one that *says so*, loudly and at once, because its `verify` states the count's rule and refuses the folder, where a baseline with the same slip would have replayed the log and silently put the job in the wrong queue. So the sixth suite's one Mo miss is an outage on restart that an operator sees, against a corruption nobody sees; and it is still a miss, the first Mo defect a baseline did not share in six suites. The erosion tally after five generations: Mo 1 carried and 1 new, Go 1 carried, Python 1 carried, Elixir 3 carried; the ten-generation prediction (Go and Python at least three, Mo at most one) is alive on both halves only if Mo's count stops here. The tax held again, 14 loops to Go's 3, six of them the shape rules (MO0301, MO0303, MO0304, MO0501, MO0105) and three the `--write` order (MO0317), the rows chapter 10 §3 and §5 already own. And the speed column, added this generation after generation four's nine-times slower lease path was found, is now measured for every program at every generation from here.

## Generation six, pre-registered (18 Sep 2026, 4:16 AM ET, before any session)

Change 6 ([[01g-job-queue-change-6]], sealed by the commit that adds this section): the archive pruned on demand and in the background as one durable record with the keys freed; a `bench` command and a **speed budget** (creates and pairs at 32 workers at least 0.8× the program's own change-3 numbers, measured by the maintainer before and after, a program under it not done); the rename rule corrected with a `next_id` boundary, as every generation-five maintainer fixed it; the generation-five bug reported as a ticket with a persistence sequence (create, archive, compact, rename, create into the old name, prune, stop, reopen, verify) that names file and directory-entry persistence separately; every declared error path reached by a test or removed. Written to press on two things the round has not: whether a maintainer given a budget finds and removes a cost it did not create (generation four's walk is still in Mo's program, nine times on the lease path), and whether a persistence sequence stated in the spec catches what the sixth suite caught after the fact.

**Setup.** Worktrees `../mo-lang-erosion6-{mo,go,python,elixir}` on `erosion6-*`, branched from the generation-five commits on `erosion5-*`; the Mo one carries the `mo` of `main` at the start (step 37's, with the fix `b0b2ac4`; the result says the commit) and the spec chapters as of that commit; the Elixir one has `mise.toml` copied in. Agents `mo-e6-{mo,go,python,elixir}` in a workspace of their own, closed when the sessions end, Claude Code on Opus at medium effort, the brief `erosion-round-suite/e6-brief.sh` (change 5's word for word with the new spec path, commit `jobq: change 6`, report to `REPORT-change-6.md`). The seventh suite is written by Fable before the sessions start and sealed in the decision log by its hash; it runs the earlier suites too. The machine quiet, `uptime` on the page, the speed row per generation as before (`measure.py`, 30,000 jobs on the VM, 1 core), and the maintainers' own `bench` lines beside it.

| prediction | threshold |
|---|---|
| P1, regressions | Mo 0 under every earlier suite; each baseline at most 1 cause beyond what it carries |
| P2, defects under the seventh suite | Mo's count no more than each baseline's |
| P3, the prune under a kill | at least one baseline loses a job the prune should have kept, resurrects a pruned one at open, or frees a key it should not; Mo does not |
| P4, the sequence | at least one program fails the spec's sequence on a change-5 folder or the directory-entry case; Mo passes both |
| P5, the tax | the Mo maintainer takes more loops than the Go maintainer |
| P6, the law | the Mo maintainer changes or adds a `never` or `invariant`, and at least one trips during the work on a wrong edit |
| P7, the budget | the Mo maintainer, told only the budget, finds the change-4 postcondition and brings the lease path back to at least 0.8× change 3 (at least 1,300 pairs a second at 32 workers on the VM, from 425 to 533); every baseline is within its budget without a change |

Fable's honest priors: P7 is the one this generation is for and the one most likely to hold; P6 has failed five times and is predicted to fail again (the laws catch shipped bugs at open, not edits); P4 is a coin toss. Recorded, not predicted: wall-clock, loops by cause, first-fix rate, lines changed, tokens read, the decision lists, which `never` each Mo edit touched, the two `bench` lines per program.

**Started** 18 Sep 2026, 4:45 AM ET (08:45 UTC), on the VM, after the memory control probe ended and with the machine quiet (load 0.26): the seventh suite `defects6.py` sealed at `48640d3` (sha256 `d4dab05cc331b7fa`), the four worktrees on `erosion6-*` from the generation-five commits (`23118a3`, `20b050c`, `a06375d`, `eb8a219`), the Mo one at `4ab5c24` with the spec as of step 37 and step 37's `mo` (`b0b2ac4`), agents `mo-e6-{mo,go,python,elixir}` in workspace `wD`, panes `wD:p1` to `p4`, the brief `e6-brief.sh`. Robert asleep; Fable watching every twenty minutes. **Interrupted:** at 5:21 AM ET a `mo` process of the Mo maintainer reached 13.4 GB and, unkillable under Herdr's `oom_score_adj -1000`, wedged the VM until Robert restarted it at 8:30 AM ET (the decision-log row of 18 Sep); the Python maintainer had finished at 5:43 AM ET; the other three sessions were resumed at 8:36 AM ET under the 4 GB guard, so their wall-clocks and loop counts carry a break, disclosed in the result.

**Continued on the Mac** 18 Sep 2026, 9:23 AM ET: the VM sessions were stopped at 8:45 AM ET with their work committed as work in progress and pushed; on Robert's Mac (M3 Max, 14 cores) the three unfinished programs got one new session each (`mo-e6-{go,elixir,mo}`, workspace `w6`, Opus, medium effort), briefed by `erosion-round-suite/e6-brief-mac.sh`, which is `e6-brief.sh` with the Mac's paths, a sentence naming the predecessor's work in progress and its `REPORT-change-6-wip.md`, and the 4 GB guard on every process. **Disclosed:** these are resumed maintainers, not fresh ones, on a second machine; each wall-clock is the sum of two sessions and each loop count carries on; the Go and Elixir programs read `/proc` for memory in their `bench`, so the move itself is work for them. Python's maintainer finished on the VM and is not rerun. P7's 1,300 pairs a second was the VM's number; on the Mac P7 is read by the spec's own ratio (at least 0.8× change 3 on the same machine). All four programs' suites run on the Mac (`e6-suites-mac.sh`). The Mo maintainer's first session named the 13.4 GB process: `mo test --sim` on a queue whose prune sent itself a `Tick` every 60 s forever (the row of 18 Sep).

### Generation six, the result (18 Sep 2026; read by Fable at 11:32 AM ET; the auditor's reading of the execution is `audit/mo-audit-2026-09-18-generation-six-execution.md`, conceded whole)

> **Corrections after the auditor's reading, 18 Sep 2026, 12:10 PM ET** (`audit/mo-audit-2026-09-18-generation-six.md`; the decision-log row "the two readings of generation six compared"). **P1 is not met as written**: it said Mo 0 under every earlier suite, and Mo carries one real cause in the third suite (a queued record with a `worker` and no lease deadline verifies, `job.mo:503`, since generation three); "no new cause" is what is true. **Python's two third-suite failures are not Python's**: the round-8 fixture writer nulls the worker for Python, so the illegal record was never written; strike "carried" from Python's cell. **The two `/queues` checks are not simply the harness's**: change 5 says a queue with only archived jobs exists "the same as `/queues` listing it"; they are one common discrepancy in all four programs, the text disputed. **Go's 0.66× at 30,000 jobs stands**, and the one rerun round at the same workload that completed before Robert's pause repeats it (change 3 at 112 pairs a second, change 6 at 70: 0.63×; creates 0.98×; added 1:36 PM ET): Go's change 6 is under its budget on pairs on this Mac, so P7's clause on the baselines fails for Go, pending a quiet Linux rerun. The table and the text below are left as first written.

**What this generation can and cannot say.** The sessions were broken by the VM's wedge and a move to the Mac, so time, loops, and tokens are recorded and compare with nothing. Fable's sealed seventh suite was invalid (every server start used a `--retain-ms` under the spec's 1,000; two logic errors the auditor found); it was run as sealed and failed at server start on every program, as predicted, and the reading is the corrected `defects6b.py`, sealed by hash before any suite ran and disclosed as written after two maintainers had finished. Change 6's own status paragraph named the slowdown's cause, so P7 is void as a test of discovery. What stands: the final programs under the six old suites and `defects6b`, run on the Mac one at a time with every exit status written (`erosion-round-suite/results/e6-*`, `e6-suites.out`), and the lead's speed rows.

| program (commit) | regressions (121) | change 1 (189) | third (66) | fourth (55) | fifth (80) | sixth (94) | `defects6b` (95 to 97 checks) |
|---|---|---|---|---|---|---|---|
| Python (`6188537`, built on the VM, one session, 59 min) | 121 | 189 | 64: the queued-with-`worker` record verifies (carried) | 55 | 80 | 94 | 90 of 95: `bench` reads `/proc` (written on Linux, never run on a Mac: machine, 2 checks); the three below |
| Go (`765aa6f`, 65 + 37 min) | 121 | 188: the `delay_ms` null (carried) | 66 | 55 | 79: `"key": null` (carried) | 92: `to` at 256 bytes (carried) | 95 of 97: the two `/queues` checks below |
| Elixir (`1e46b99`, 115 + 52 min) | 120: a token with a space (carried) | 128 of 129: the old-log category unread (carried) | 63 of 65: the 1 MB body, the restart after a full disk (carried) | 53: the budget at the window's edge (carried) | 79: a repeated flag (carried) | 94 | 95 of 97: the two `/queues` checks below |
| Mo (`53ee60d`, 68 + 23 min), binary and `mo run` alike | 121 | 189 | 64: the queued-with-`worker` record verifies (carried since generation three; generation five's table said 66 without having run it) | 55 | 80 | **94: generation five's Mo-only defect is fixed** (the folder reopens after a compaction, a rename, and a stop) | 92 of 95: the three below |

**Every `defects6b` failure is the harness's or the machine's, none a program's.** (1) Two checks expect `/queues` to list a queue whose only job is archived; **all four programs omit it, identically**. Change 2 says "every queue that has at least one job in any state" and gives `/queues` no archived count; four maintainers in four languages read it the same way and Fable's suite read it the other. A spec sentence to settle, not a defect. (2) One `prunerecord` check looks for a number in the prune record to corrupt; Mo and Python write the cutoff as a timestamp, which the spec allows ("naming the cutoff"). (3) Python's `bench` reads `/proc`. The new category `change5` (each language's own change-5 program writes, archives, renames, compacts, renames again, stops; the change-6 program verifies, opens, counts, serves) passed in all four.

**Generation five's third suite, measured today for the first time** (the correction above): Go 65 of 66 (the 1 MB body answered with a broken pipe, once), Python 64, Elixir 63 of 65, Mo 64 in both runtimes. Nothing new eroded there either; the claim now has its evidence.

**Speed, the lead's rows** (`e6-speed-mac.sh`, `measure.py`, 30,000 jobs, `MO_CORES=1`, change 3 and change 6 alternating, two rounds; the Mac was not quiet: Robert's own use, load 6 to 8, Zoom and the window server at the head of `ps`; both Mo programs built with `main`'s `mo`):

| program | creates a second, change 3 → 6 (rounds 1, 2) | pairs at 32 workers, change 3 → 6 | ratio on pairs | restart on the 30,000-job log |
|---|---|---|---|---|
| Mo, binary | 4,349 → 6,948; 7,431 → 7,709 | 2,429 → 3,177; 3,652 → 3,675 | 1.31, **1.01** (round 1's first run was cold) | 0.81 to 0.89 s → 0.98 s |
| Python | 7,386 → 8,518; 8,805 → 8,892 | 3,377 → 4,213; 3,937 → 4,188 | 1.25, 1.06 | 0.70 → 0.75 s |
| Elixir | 6,515 → 7,791; 6,748 → 7,866 | 3,986 → 4,876; 4,964 → 4,919 | 1.22, 0.99 | 1.9 to 2.0 s → 0.56 s (the maintainer's parallel replay) |
| Go | 216 → 204 | 104 → 69, then at 5,000 jobs 101 → 100 and **67** → 108 (change 3 itself swings 67 to 104) | noise on a disk-flush-bound path | 0.16 → 0.17 s |

Every program is at its change-3 rate. **Mo's lease path is back** (generation five: 425 pairs a second at 32 workers on this machine; now about 3,700), by the one-line postcondition change the spec pointed at. **The rates do not compare across languages on a Mac:** Go's `File.Sync` asks macOS for a full flush to the disk (`F_FULLFSYNC`) on every write; Mo's runtimes call plain `fsync` (`toolchain/src/blocking.zig:114`, `mo_rt.c:8303`), which on macOS does not reach the platter, and Python's `os.fsync` is the same. So on this machine Mo's "on disk before `Ok`" is weaker than Go's, and Go's 100 pairs a second is what the stronger promise costs. A semantic row; the fix is in step 39.

**Against the predictions.**

| prediction | outcome |
|---|---|
| P1, regressions: Mo 0, each baseline at most 1 new cause | **held**: no program has a new cause under any old suite; Mo lost one (the generation-five defect, fixed) |
| P2, the seventh suite: Mo no more than each baseline | **held at a tie of zero**, under the corrected suite only |
| P3, a baseline loses something under the prune and the kill | **failed**: nobody did, under an oracle that was broken as sealed and is right in `defects6b` |
| P4, a program fails the sequence on a change-5 folder or the directory-entry case | **failed on the first half** (all four open their own change-5 folder); the second half is untestable from outside (no program but Go and Elixir offers a kill point between the rename and the directory's fsync; Mo has no `Fs` row that syncs a folder at all: the Mo maintainer's toolchain bug 6) |
| P5, Mo takes more loops than Go | recorded, not read: Mo 29, Go 8, Elixir 18 by their reports, across broken sessions (Python, one session, lists its own by cause) |
| P6, a Mo `never` or `invariant` trips on a wrong edit | **failed, the sixth time**: the Mo maintainer added one `never` and changed one `ensures`; none tripped on an edit; the same in Python, Go, and Elixir by their reports |
| P7, the Mo maintainer finds the cost told only the budget | **void**: the spec named the cause. What is true: given a budget and the cause, the maintainer fixed it in one edit and the rate is back, 1.01× on the lead's second round |

**Reading.** Generation six is the first generation in which Mo's count went down: six generations, one Mo-only defect shipped and then fixed by the next maintainer from a ticket. Nothing eroded in any language under any suite. The laws were silent again; at six of ten generations the language rule's ledger has zero catches, and its threshold is two. The budget worked as a device (every program at its change-3 rate, Mo back from one-ninth) and proved nothing about discovery. The generation's real findings are about the experiment and the runtime, not the programs: a sealed suite that had never been run; a runner that swallowed a usage error for a whole generation; a simulator that takes a machine down on a process with a perpetual timer; `for _ in 0..n` building its range; no way to sync a folder from Mo; and `fsync` on macOS.

## Related

- [[d43-five-measurements]]
- [[control-run-8]]
- [[control-run-10]]
- [[01c-job-queue-change-2]]
- [[01d-job-queue-change-3]]
- [[01e-job-queue-change-4]]
- [[01f-job-queue-change-5]]
- [[interpreter-step-31]]
- [[roadmap]]
