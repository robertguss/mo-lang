---
title: "Sampling as verification: five regenerations of the queue's board, pre-registered"
created: 2026-09-15
updated: 2026-09-17
type: plan
tags: [verification, agents, research]
sources: [directions/d43-five-measurements.md, plans/control-run-7.md, spec/programs/01-job-queue.md, decisions/decision-log.md]
status: done
---

# Sampling as verification

Measurement 2 of [[d43-five-measurements|direction 43]], decided 15 Sep 2026, 20:50 (decision log): one module of a finished program is regenerated five times by fresh Opus sessions from its stripped spec, a driver feeds all five the same random operation sequences, and every disagreement is read as a defect or a spec hole and compared with what the hidden suite finds. The hypothesis: N implementations of one spec disagree exactly where a defect is, so a spec'd module can be verified by sampling with no suite written. It runs in one pane before [[control-run-8]], while that round's spec and plan are written; if it finds defects, disagreement joins round 8's pre-registration as a fourth oracle on the changed modules. Predictions were written before any session started.

## The module

`Jobq.Board` from round 7's Mo job queue (`../mo-lang-control7-mo/examples/programs/jobq/board.mo`, 698 lines, 10 tests, one property): the queue as a value, with one pure entry point, `decide(board, call, now) : Decision`, that takes a call (create, fetch, list, remove, lease, ack, fail, health) and the clock and returns the board after it, the answer, and the records the store must hold before the answer is sent. It holds the lease and retry logic the decision named: the sweep that puts run-out leases back, the oldest-first order per queue, the attempt count and the dead rule, the race between two workers. It is pure, so five variants can be compared with no socket and no real clock; the process, the store, and the HTTP layer around it are untouched and shared.

## The stripped spec

A script of the lead's (`sampling-as-verification-suite/strip.py`) rewrites `board.mo` to what a fresh agent gets: the module line, the `expose` list, the `use` line, the `intent`, the `never`, every type with its comments, the signature of every exposed function and of every function the tests call, each with its comment and its `requires` and `ensures` lines, the ten tests and the property as written, and no `verified:` line. Every body is gone and every other function is gone, so the decomposition under `decide` is the agent's. Round 7's program spec is in the worktree, and so is the rest of the program: `job.mo` (the job's states and transitions), `queue.mo` (the process that calls `decide`), and the `data/` folders with `jobq.expected`, the program's own check transcript.

## The harness

Before stripping, one worker session writes `examples/programs/jobq/sampler.mo` against the original `board.mo`: a `main` that reads a script of lines `<ms> <worker> <command> [args]`, builds the board from an empty store at a fixed start time, calls `decide` once per line with `now` at start plus the line's milliseconds, and prints one line per call: the outcome and every record the decision writes, jobs through `shown`. The harness is then frozen; the five variants are compared through it. The lead verifies it by playing the demo session's commands through it and reading the outcomes against `jobq.expected`.

## The driver

`sampling-as-verification-suite/sample.py`, the lead's: from a seed, forty operations over two queues, three workers, job ids `j_1` to `j_8`, `max_attempts` 1 to 3, `lease_ms` 100 to 1,000, the clock advancing 0 to 600 ms a line, commands weighted toward lease, ack, and fail. One thousand seeds. For each seed the transcript of the original and of the five variants; a disagreement is the first line where a variant's transcript differs from the majority of the five, and it is grouped with every other seed whose first differing line has the same shape (the same command and the same pair of outcomes). The lead reads each group against the spec and the tests and names it a defect (the spec decides and the minority is wrong), a majority defect (the spec decides and the majority is wrong), or a spec hole (the spec does not decide). The original is not in the vote; its disagreements with the vote are read the same way.

## The ground truth

Round 7's hidden suite (`control-run-7-suite/defects.py`, 121 checks) is run on the whole jobq program with each variant's `board.mo` in place, under `mo run`, `--only` the tests that reach the board (`lifecycle`, `listing`, `expiry`, `race`, `health`). A variant's suite defects are the checks it fails; the original fails none (round 7). A defect the suite finds is *found by sampling* when that variant is in the minority of a disagreement group the lead read as a defect.

## Setup

| what | where |
|---|---|
| worktree | `../mo-lang-sampling`, branch `sampling`, planned from `main` with the round 7 jobq copied in; as run, branched from `control7-mo` (the Result below) |
| pane, agents | `w7:p7`; `mo-sample-0` writes the harness, `mo-sample-1` to `mo-sample-5` regenerate, one fresh session each, sequential |
| branches | `sampling-k` from `sampling` after the stripped file is committed; each variant is one branch |
| the brief | "The bodies of `board.mo` are gone; write them so `mo check` and `mo test` on `examples/programs/jobq` are green and `mo run main.mo -- check data/demo data/session.txt` matches `jobq.expected`; touch no other file; commit when green; report loops by cause, wall-clock, and the decisions the spec did not cover" |
| what a session sees | the worktree as it is, this page's name never; the token count of its pane is read before its report (measurement 5) |

## Pre-registered

| prediction | threshold |
|---|---|
| P1, regeneration is feasible | every variant is green within 90 minutes of worker time |
| P2, sampling finds the suite's defects | of the suite defects across the five variants, at least half are found by sampling; if the suite finds none, P2 is unread and P3 decides |
| P3, sampling finds holes | at least two disagreement groups are spec holes, each a row for `01-job-queue.md` or for round 8's change spec |
| P4, the opposite | if the five agree on every seed and the suite finds no defect in any variant, sampling has no signal on a spec'd module of this size and the fourth oracle is dropped from round 8 |

Recorded, not predicted: loops to green by cause per variant, wall-clock, output tokens, tokens read (the pane's count), lines per variant, the number of disagreement groups, and the first line at which each group diverges.

## Result

Run 15 Sep 2026, 20:30 to 22:10 UTC, on the exe.dev VM, worktree `../mo-lang-sampling` branched from `control7-mo` (round 7's Mo queue under the step 27 toolchain it was written with). The harness `sampler.mo` (210 lines, one Opus session, 3 min 39 s) was frozen at `4dd7e77`; the stripped `board.mo` (299 lines of 698: 13 signatures, 10 tests, one property) at `682e7db`; the five regenerations on `sampling-1` to `sampling-5`, each verified by the lead (`mo test board.mo` 10 of 10, every other module green, the check transcript byte-for-byte `jobq.expected`, the sampler demo). The pane's context count was read with `/context` before each report.

| variant | wall-clock | loops | lines | context tokens |
|---|---|---|---|---|
| v1 | 7 min 48 s | 3 | 659 | 153k |
| v2 | 8 min 25 s | 3 | 672 | 160k |
| v3 | 7 min 09 s | 3 | 666 | 171k |
| v4 | 9 min 25 s | 3 | 742 | 184k |
| v5 | 8 min 38 s | 3 | 678 | 170k |

**The random driver found nothing.** Three batches, the pre-registered one and two added when the first came back clean: 1,000 seeds of 40 operations; 300 seeds of 200; 40 seeds of 1,500 with ids up to 1,200 and creates weighted so the listing cap and the id reservation block are crossed. Every one of the five variants agrees with every other and with the original on every line of every seed, 132,000 operations in all. One difference had to be canonicalized away before that was true: the order in which a sweep's put-back records are listed (lease-end order in the original, job-number order in v1), which the store cannot observe since every key's last write is the same; the driver now compares a decision's writes as the store's end state. No test in `board.mo` ever failed for any regeneration.

**The rebuild path, which the sampler cannot reach, found one.** The workers' "decisions the spec did not cover" lists all named the same places: what `rebuilt` does with a log that has no `ids` record, an `ids` that is not a number, a record under the wrong key, a queued job whose `attempts` already equal its `max_attempts`. Ten hand-written logs (`sampling-as-verification-suite/rebuild-cases/`, played through each variant's whole program with `jobq check`) agree on nine. On the tenth, a queued job at its `max_attempts`, the original, v1, and v3 crash the queue process on the first lease (`job.mo`'s `requires` in `leased` trips; the check shows `process crashed`), while v2, v4, and v5 pass the job over and hand out the next. The state is unreachable by the API (`attempts` reaches `max_attempts` only on the way to `dead`) and reachable by a hand-edited or foreign log; the spec's replay rule says a record that is not a job refuses the folder at open, and says nothing about a job in an impossible state. Three of six implementations, the original among them, turn it into a crash at lease time rather than a refusal at open.

**The ground truth.** Round 7's suite, the five categories that reach the board (`lifecycle`, `listing`, `expiry`, `race`, `health`), run on the whole program with each variant's `board.mo` in place: 52 checks, 0 defects, for the original and for every variant; the suite separates nothing here, as P2 allowed for.

**The loops, read for measurement 5.** Fifteen loops over five regenerations, three each, the same three every time: an assignment on a `case` arm's line (MO0101, five of five, first fix right five times); a `for` with a pure body that must be a `reduce` (MO0501, four of five, first fix right every time) or a one-field variant matched by name (MO0212, two of five) or a helper called before it was written (MO0201, two of five); and MO0317 on every module that uses `Jobq.Board`, whose `verified:` lines went stale when the board changed and had to be rewritten one module at a time in dependency order (five of five; the first fix failed once, when `--write` on the board alone was expected to clear its dependents). First-fix rate: MO0101 5/5, MO0501 4/4, MO0212 2/2, MO0201 2/2, MO0317 4/5. The MO0317 loop is the toolchain's cost, not the agent's: a changed module stales every dependent's line, and nothing says so in one place.

## Reading, against the predictions

| prediction | threshold | result | held |
|---|---|---|---|
| P1, feasible | every variant green within 90 min | 7 to 9.5 min each, no test failed | yes |
| P2, finds the suite's defects | at least half | the suite finds none in any variant; unread | — |
| P3, finds holes | at least two disagreement groups are spec holes | one, and from the directed rebuild probe, not the pre-registered driver | no |
| P4, the opposite | five agree everywhere and the suite finds nothing | true on `decide`; false on `rebuilt` for one hand-made input | mostly |

**What it says.** For a module at this spec altitude, signatures, contracts, intent, `never`, and ten tests, five fresh Opus sessions write behaviourally identical code over everything the API can reach; the spec is complete for this module, and sampling has no defect to find there. That is the strongest evidence yet for measurement 1 (bodies as cache): five regenerations of one module at completeness 1.0, before that measurement runs. Where the spec is silent, the input space outside the API, three of six implementations disagree, and the disagreement is a real one (a crash against a skip). So sampling verifies exactly what the spec does not pin, which is where it would be worth its tokens, but only when the driver reaches that space; a random operation driver does not, and a hand-written probe informed by the regenerators' own decision lists did. Disagreement joins round 8 as a fourth oracle in that form only: the workers' "decisions the spec did not cover" lists are read for inputs the suites do not send, not as a driver over the API. Cost: five sessions at about 8 minutes and 170k context tokens each, plus one for the harness.

**Rows.** For the spec: a queued job at its `max_attempts` in a log is refused at open like a record that is not a job (Fable's recommendation; the original crashes instead). For the toolchain: MO0317 on a dependent module should name the module that changed and offer the one `--write` order, since every regeneration lost a loop to it. For measurement 1: the board's completeness is 1.0 on this evidence; the ledger's compaction and the agent program are where it should fall.

## Related
- [[d43-five-measurements]]
- [[control-run-7]]
- [[control-run-8]]
- [[interpreter-step-30]]
- `spec/design-v0/08-milestone.md`, the measure
