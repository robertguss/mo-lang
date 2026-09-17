---
subject: the probe naming the cause of generation four's speed loss on the Mo queue's lease path
author: Fable (the lead)
date: 2026-09-17, 20:35 UTC
filed_against: 69860b0
read_before_auditor: yes, with one caveat. Fable had not opened `audit/mo-audit-2026-09-17-gen4-speed-probe.md` when this was written. Robert's message announcing it relayed its verdict and four points in prose (a contracts-on regression isolated to `mo_disown_in` under `List.all?`; contracts off within 3 percent; the 46 against 173 MiB resident memory; the missing source diff; two standing concerns). That relay was read; the file was not. The source diff the relay asked for is added to the bundle beside this reading (`gen4-speed-probe/board-sweep.diff`, `board-decide-gen4.txt`, `emitted-a27.txt`, `mo_rt-disown_in.txt`), against 69860b0's outputs, unchanged.
evidence: audit/evidence/2026-09-17/README.md, item 4; the row of 17 Sep, 19:25 UTC in mo-wiki/decisions/decision-log.md (Fable's first reading, written before the relay); mo-wiki/plans/erosion-round.md, the speed row
---

# Fable's reading: the nine times, named

## The measurement

Both queues rebuilt with step 35's `mo` from branches `erosion3-mo` and
`erosion4-mo`, `measure.py` at 30,000 jobs, `MO_CORES=1`, on the VM after the
fuzz hour, nothing else running. Pairs a second at 32 workers:

| run | generation three | generation four |
|---|---:|---:|
| contracts on, under `perf` | 940 | 519 |
| contracts on, under the runtime surface | 1,664 | 533 |
| `MO_CONTRACTS=0` | 1,793 | 1,736 |

The gap is the contracts, whole: with them off the two generations are within
3 percent. Under `perf` generation three loses more than four (940 against
1,664) because it is the CPU-bound one at this rate; the surface run is the
cleaner pair. The VM's disk caps the fast queue near 1,700 (one fsync a
change, about 990 syncs a second on this disk, the row of 15 Sep), which is
why the ratio here is three where the Mac's was nine: the slow path costs the
same per request on both machines, and the fast path is capped here.

## The cause, at three levels

1. **The program.** Change 4's maintainer added to `sweep` the postcondition
   `ensures all_ends(result.board).all?(fn(e) !old_enough?(board, e.1, now) end)`
   (the diff in the bundle: generation three's `sweep` has the two `ensures`
   over leases and waits, which are small; four adds the third over `ends`,
   which is every finished job's page flattened). `decide` calls `sweep` first
   on every request (`board-decide-gen4.txt`), so every lease and every ack
   walks every job ever finished. Chapter 3 runs contracts in every build. That
   is O(finished jobs) per request, and it is what `MO_CONTRACTS=0` removes.
2. **The runtime, which Fable's first reading missed and this one adds.** `perf`
   puts 23 percent of the server's samples in `mo_disown_in` itself (self
   time), called once per element from the emitted lambda `a27`
   (`emitted-a27.txt`: `mo_disown_in(cap[0])` at the top of the closure's body).
   `cap[0]` is `board`, captured because the lambda calls `old_enough?(board,
   e.1, now)`. `mo_disown_in` on a record walks every field and, for each map
   it holds, does a table lookup (`mo_rt-disown_in.txt`); `Board` is a record
   of maps of pages. So the binary pays a structural walk over `Board` **per
   element visited**, on top of the program's O(n): the closure-call cost of
   capturing a large record. Generation three's lambdas capture `now`, a
   scalar, which is why they are cheap even where they run. Fable reads this
   as a backend cost worth its own row: disowning a closure's captures once
   per call is the runtime's choice, not the maintainer's, and it multiplies
   whatever the maintainer wrote.
3. **What was not the cause.** Not the key map, not the board's new `never`
   (`a job is on the live board and in the archive at once after an open`,
   which runs at open), not the scheduler, not the store. The speed row's
   suspects of 16 Sep are cleared.

## The memory number

Resident memory after the pairs phase: generation four 46 MiB, generation
three 173 MiB. Read plainly, that is a large one-sided win for four. Fable does
not read it so: with contracts off, generation four sits at 169 MiB and three
at 168, and generation four with contracts on had 40 MiB already after the
creates against 139 without. The low number appears only with the expensive
contract on, so it is a side effect of that contract, not of the program's
design: the postcondition is a call made as a whole statement, which is a
safe point where the region compacts (step 29b), and its walk touches the
whole board, so the region is compacted far more often and more thoroughly
than in the runs where nothing walks it. A program whose garbage is freed
because a contract happens to walk its state on every request has found a
cost, not a saving. This deserves its own probe (the same server with a cheap
`ensures` that touches `board` once per request) before anyone counts it as a
win; Fable has not run that probe.

## What this means for the rules under audit

- **RC2, the speed row.** Fable's decision (the row of 19:25 UTC) stands: the
  row is read as measured, contracts on, because that is what ships, and
  chapter 3's rule that contracts run in every build is the language's
  choice. The runtime rate is generation three's. Two readings are possible
  and the auditor should choose between them explicitly: (a) the speed row
  measures the shipped program, so the slowdown counts against Mo whatever
  its cause; (b) the row measures the runtime, so a maintainer's O(n)
  contract is program erosion, the erosion round's subject, not RC2's. Fable
  holds (a) for the row and (b) for the reading of the cause, and records
  both so the disagreement, if any, is over which the rule means.
- **The erosion round.** This is erosion the fifth suite could not see (77
  checks green). The round now records speed per generation (the row of 16
  Sep). What a maintainer needed and did not have: a number that grows with
  the state on a hot path. The surface's `/slowest` shows `Sweep` growing
  (the bundle's `surface4.slowest`); no maintainer looked, and nothing made
  them. That is a chapter 10 candidate: a diagnostic for a contract whose
  cost scales with the collection it walks, at check time (the checker knows
  the contract calls `all?` over a function of the state) or at run time (the
  surface knows the update's time by name). Fable prefers the check-time
  form, since the run-time one needs load to show.
- **Program 7.** Its request path will carry contracts, and its payloads are
  `List(UInt8)` through the crypto brick. The two ratios compound in one
  direction: a contracts-on, `List(UInt8)` program will measure well below
  the bricks page's raw numbers. The bricks page must say so before program 7
  is measured against it; Fable will add the note (a dated edit on its own
  page), and program 7's spec will name the request path's contracts as a
  thing the speed row reads.

## What this reading did not do

- No run on the Mac, where the nine times was first seen; the VM's disk cap
  makes the ratio three. The cause is the same code; the ratio is the disk's.
- No run of the closure-capture cost in isolation (a micro-benchmark of a
  lambda capturing a record against one capturing a scalar). That is the
  probe that would size level 2 against level 1, and it is not run.
- No fix. Nothing in the evidence branches is changed; the round's rule is
  that the maintainers' programs stay as they left them.
- The gap the auditor named is real: the bundle at 69860b0 held the numbers
  and the `perf` chains but not the source diff, so the source-level cause
  rested on the decision row's word. The diff and the emitted C are in the
  bundle now, and the evidence README's rule for future speed probes is
  amended: the diff at the named sites travels with the numbers.
