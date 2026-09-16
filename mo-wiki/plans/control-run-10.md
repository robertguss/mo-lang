---
title: "The control run, round 10: the Elixir round, pre-registered"
created: 2026-09-16
updated: 2026-09-16
type: plan
tags: [runtime, verification, agents, roadmap]
sources: [directions/d42-elixir-round.md, plans/control-run-7.md, plans/control-run-8.md, spec/programs/01-job-queue.md, spec/programs/01b-job-queue-change.md, spec/design-v0/01-premise.md, decisions/decision-log.md]
status: done
---

# The control run, round 10

The BEAM is chapter 1's null hypothesis and it has only ever been argued on paper ([[d42-elixir-round|direction 42]], Robert, 15 Sep evening). This round puts it in a pane: one fresh Opus session writes round 7's job queue in Elixir from the same spec, with dialyzer, credo, and ExUnit as its checks, and a second fresh session makes round 8's change to it from the same change spec. Both hidden suites read the result beside Mo's, Go's, and Python's rows from rounds 7 and 8. Fable brought the round forward from "after round 9" to the night of 15–16 Sep, since round 9 waits on Robert's Pi provider logins and this one waits on nothing (decision log, 16 Sep). Predictions were written before the session started.

## What decides

If Elixir matches Mo on the suites and the runtime rows, Mo's delta over the BEAM is only what is left: static types, unforgeable capabilities, a deadline on every wait, one static binary, no ecosystem; each of those then has to be measured on its own or dropped. If Elixir falls behind on reliability or on the runtime rows, the language layer earns its place. Dependencies are read as chapter 1 says: every Hex package at run time plus every tool, against Mo's zero.

## Setup

| what | where |
|---|---|
| worktree | `../mo-lang-control10-elixir`, branch `control10-elixir` from `main` at `a2d220a`, with `toolchain/`, `examples/`, and `mo-wiki/` removed and the two spec pages at `spec/` |
| the program | `experiments/control-run/elixir/jobq/`, a Mix project; Elixir 1.18.5 on OTP 27 through `mise`, installed 16 Sep 00:10 for this round |
| agents | `mo-r10-elixir` writes the program from `spec/01-job-queue.md`; after Fable's verification and the round 7 suite, `mo-r10-elixir-change`, a fresh session, makes `spec/01b-job-queue-change.md` |
| the brief | round 7's Mo brief in shape: the spec by path, the checks named (`mix compile --warnings-as-errors`, `mix dialyzer`, `mix credo --strict`, `mix test`), a `check.sh`, a `bench/` client, the wall-clock and loops reported, the decisions the spec did not cover listed; then round 8's brief for the change |
| the suites | `control-run-7-suite/defects.py` on the first program; `control-run-8-suite/regressions.py` and `defects.py` (with `--old-serve` the first program) on the changed one; `oracle4.py` with an Elixir log writer once the log's shape is known |
| measure | `control-run-8-suite/measure.py` on the changed program, alone on the disk, in the same session as Go's and Python's round 8 numbers were taken; Mo's row is round 8's binary |

## Pre-registered

| prediction | threshold |
|---|---|
| P1, reliability, round 7's suite on the first program | Elixir 0 or 1 defects of 121 (Mo, Go, Python were 0, 0, 0) |
| P2, reliability, round 8's suites on the changed program | regressions 0; defects at most 1 (Mo 0, Go 1, Python 0) |
| P3, speed and memory, native | pairs a second at 32 workers between Python's 325 and Mo's 1,420; memory at 100k jobs above Go's 81 MiB and below 300 MiB |
| P4, the feedback loop | dialyzer, credo, and the tests over the finished program above 10 s cold; `mix test` alone under 5 s |
| P5, dependencies | at least 3 Hex packages counting dialyzer and credo as tools, and `jason` or the standard library's JSON at run time |
| P6, the runtime rows | the kill under load loses no acknowledged write; a crashed queue process is restarted by its supervisor and the service keeps answering, where Mo's changed queue stops answering ([[control-run-8]], the outage) |

**The reading.** P6 is the row that decides the BEAM question: if Elixir's supervision restores service where Mo's program did not, that is the null hypothesis winning on the one row the runtime claims as its own, and the language page has to say why Mo's `restart: :never` and the send-then-wait pattern were the natural choice for a Mo program. P1 and P2 read the reliability claim as in round 8. P3 to P5 are recorded against the same columns.

## Result

Run the night of 15–16 Sep 2026 on Fable's decision, while Robert slept. `mo-r10-elixir` started 23:56 UTC in `w7:pH` and was green on all four checks and `check.sh` at 00:27 (31 minutes; 44 with its bench and report), tagged `r10-v1`; `mo-r10-elixir-change` started 00:43 and was green at 01:00 (16 minutes). Both reports are in the worktree (`REPORT.md`, `REPORT-change.md`) and copied to `control-run-10-suite/`. Verified by Fable: `mix compile --warnings-as-errors`, `mix dialyzer` (0 errors), `mix credo --strict`, `mix test` (104 tests, 4 properties), `check.sh`, an escript of each version. The suites were run on the escripts; `measure.py` ran at 01:44 with nothing else on the disk.

### On Robert's measure, beside rounds 7 and 8

| | Elixir | Mo, native (round 8) | Go | Python |
|---|---|---|---|---|
| defects, round 7's suite on the first program (121 checks) | 4 checks, 2 causes | 0 | 0 | 0 |
| regressions after the change | 0 (the same 4 checks) | 0 | 0 | 0 |
| defects, the change's suite (189 checks) | 3 checks, 1 cause | 0 | 1 | 0 |
| creates a second, 100k jobs | 2,765 | 2,246 | 929 | 770 |
| pairs a second, 1 worker / 32 workers | 385 / 2,870 | 266 / 1,420 | 419 / 428 | 317 / 325 |
| resident memory at 100k jobs | 237 MiB | 113 MiB | 81 MiB | 189 MiB |
| feedback loop, warm | 6.99 s (dialyzer, credo, the tests) | 0.81 s | 14.4 s | 7.5 s |
| third-party at run time / tools | 0 / 3 (`credo`, `dialyxir`, `stream_data`, plus 4 transitive) | 0 / 0 | 0 / 1 | 1 / 2 |
| wall-clock, the program / the change | 31 min / 16 min | 60 min (round 7) / 34 min | 28 / 15 | 27 / 16 |
| loops, the program / the change | 14 / 7, every first fix right | 21 (round 7, both tasks) / 9 | 4 (both tasks) / 8 | 10 (both tasks) / 6 |

The two causes under round 7's suite: a bearer token with a space is accepted (Go's round 6 defect, again), and a torn last line is dropped when read but not cut from the file, so the next run appends after it and the run after that finds the log corrupt and exits 1; that second cause is the one the change's suite finds again when it tears the old folder, and it is a durability defect by the spec's own words. Every check specific to the change passed (185 of 188). The Elixir program answers `/health` before its replay is done, so the restart row is not comparable and is left out. Elixir's own bench read 4,974 pairs a second at 32 workers against Fable's client's 2,870; the client's number is the row, as for the other three.

**The fourth oracle** (`oracle4.py --log-format elixir`, fourteen inputs): a queued record already at its `max_tries` is leased and its `tries` go past `max_tries` (Go and Python refuse the folder, Mo's service goes down); a retry sent with a JSON body is `400` where the other three ignore the body; the rest agree with the majority. **P6 was not probed** for a crashed queue process: the oracle's impossible record does not crash the Elixir queue, and no cheap way to kill its GenServer from outside was built tonight; the row stays open.

## Reading, against the predictions

| prediction | threshold | round 10 | held |
|---|---|---|---|
| P1, reliability, the first program | 0 or 1 defects | 2 causes, 4 checks | no |
| P2, the changed program | regressions 0, defects at most 1 | 0; 1 cause, 3 checks | yes, on causes |
| P3, speed and memory | pairs between Python's 325 and Mo's 1,420; memory between 81 and 300 MiB | 2,870, twice Mo; 237 MiB | no on speed, in Elixir's favour; yes on memory |
| P4, the loop | above 10 s cold, `mix test` under 5 s | 6.99 s warm for all four, `mix test` 2.4 s | yes on the tests; the warm loop beat the guess |
| P5, dependencies | at least 3 Hex packages with tools, a JSON package at run time | 0 at run time (OTP 27's `:json`), 3 tools + 4 transitive | no: the run-time column ties Mo |
| P6, the runtime rows | the kill loses nothing; a crashed queue restarts and the service answers | the kill under load lost nothing (both suites); the queue process killed from outside three times under load, `/health` back in 215 to 583 ms each time, 0 acknowledged writes lost of 32,765; but four kills inside 2.1 s cross the supervisor's default restart intensity and the node exits | yes, with a limit the program never set |

**What it says.** The BEAM null hypothesis is alive, and P6 is now its row. One fresh Opus session wrote the queue in Elixir in 31 minutes, half the Mo session's 60 in round 7, with no run-time dependency at all, since OTP 27 ships JSON, and the changed program is twice as fast as the Mo binary at 32 workers on the same disk. Where Mo wins is exact: reliability (0 defects against 2 causes, and the torn-line bug is the kind of durability slip Mo's store recipe and its `never` at rest are written for) and the loop (0.81 s against 7 s). The one row the runtime claims as its own, a crashed process with the service still answering, went to the BEAM on the Mac on 15 Sep, 22:45 local: with the Mac session's `p6.py` (`control-run-10-suite/`), eight clients creating, leasing, and acking on keep-alive connections at about 11,000 requests a second, the queue GenServer was killed from a second node with `Process.exit(pid, :kill)` at 1.7 s and 4.7 s and the store at 7.7 s; `/health` answered 200 again 261, 393, and 583 ms after each kill, the `rest_for_one` tree restarting the queue by replaying the log and the listener with it; 735 of 99,060 requests in those nine seconds failed (connections dropped by the listener's restart, eight 503s from the queue's call timeout); of 32,765 acknowledged jobs, 0 were lost, on the running service and on a fresh open of the same folder. Round 8's Mo program under the same shape of failure stopped answering every request. The Elixir maintainer never wrote a line for this: the supervision tree in `server.ex` is 70 lines, most of them the module doc. The limit found by the probe the brief did not name: five kills 400 ms apart cross the supervisor's default intensity (3 restarts in 5 s), the tree gives up, the escript exits with "the service stopped: :shutdown", and every request refuses from there; the folder reopened at 7,530 done against the clients' 7,529 acks (the one more an ack whose reply was in flight). So the BEAM's row is real and bounded by a default the program never set, and Mo's row is that its program never handled a down queue at all.

The honest reading of chapter 1's null hypothesis after round 10: the language layer has earned reliability and the loop; the BEAM has taken speed, time to write, the dependency tie, and P6, the runtime row. What the runtime and process model were argued to give, restart with the service answering, the BEAM gives today from a supervisor the program did not have to think about, and Mo's spec-as-written program did not give it. That is the row the language page (`09-language-after-the-rounds.md`) has to answer, and the erosion round's change 2 is the first test of whether a Mo program can be written to give it: the same probe runs on the Mo change 2 program when it exists, and on the Elixir one again under the same script.

**Rows.** For the language page: a `never` at rest on the log (round 7's `store.mo`) is what would have caught the torn line; Elixir has no place to write it. For the erosion round: the Elixir program joins generation two with change 2. For measurement 5: 21 loops over two sessions, every first fix right, none a language law.

## Related
- [[d42-elixir-round]]
- [[control-run-8]]
- [[control-run-7]]
- [[roadmap]]
