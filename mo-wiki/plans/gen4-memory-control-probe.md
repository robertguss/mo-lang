---
title: "The generation-four memory control probe: is the low RSS the contract's walk or the design?"
created: 2026-09-18
updated: 2026-09-18
type: plan
tags: [runtime, programs]
sources:
  [
    plans/erosion-round.md,
    decisions/decision-log.md,
  ]
status: in-progress
---

# The generation-four memory control probe

The speed probe of 17 Sep 2026 (`audit/evidence/2026-09-17/gen4-speed-probe/`)
measured generation four's jobq at 46 MiB resident after the pairs phase
against generation three's 173 MiB, both with contracts on; with contracts off,
169 and 168. The auditor's reading counts the 46 MiB as a memory win of the
design, a CPU-for-memory trade; Fable's reading says it is a side effect of
change 4's expensive postcondition (a whole-statement call that walks every
finished job on every request, which is also where the region compacts, step
29b) and not of the design. The comparison of 18 Sep
(`audit/comparisons/2026-09-18-gen4-speed-probe.md`, row
`AUD-COMP-GEN4-RSS-001`) leaves the interpretation to Robert and names the
test: a cheap contract at the same point. Neither reading is established until
this probe runs. **Pre-registered here before the run.**

## Predictions, written before the run

- **Fable's hypothesis (H1, the compaction point):** a cheap `ensures` on
  `sweep` that touches `result.board` once per request, without walking the
  finished jobs, keeps the region compacting at the same safe point, so the
  RSS after pairs stays near generation four's 46 MiB while the rate returns
  to near generation three's. Deleting the postcondition altogether returns
  the RSS to about 169 MiB (as contracts off does).
- **The auditor's reading (H2, a design benefit):** the low RSS follows from
  what change 4 keeps and frees, not from the walk; then the cheap `ensures`
  variant and the deleted-`ensures` variant both sit near 46 MiB with
  contracts on, and the rate is the only thing that changes.
- **A third outcome (H3, the walk itself frees):** the low RSS needs the walk
  over finished jobs (its allocation pattern, not the compaction point); then
  the cheap variant sits near 169 MiB and only the original postcondition
  gives 46.

Fable predicts H1 with the numbers: cheap variant 40 to 60 MiB after pairs and
1,300 to 1,700 pairs a second at 32 workers; deleted variant 150 to 180 MiB.
The row for Robert is written after the numbers, citing the outcome by its
letter.

## Orientation

The worktrees `../mo-lang-erosion3-mo` and `../mo-lang-erosion4-mo` (branches
`erosion3-mo`, `erosion4-mo`), rebuilt with step 35's `mo`; the probe scripts
`build.sh`, `run.sh`, `measure.py`, `surface.sh` under
`audit/evidence/2026-09-17/gen4-speed-probe/`; the diff `board-sweep.diff`
there (the line to vary is the third `ensures` of `sweep` in
`examples/programs/jobq/board.mo`, generation four's line 380). The
measurements are `measure.py`'s: creates a second, pairs a second at 32
workers, RSS after the creates and after the pairs, the restart. `uptime` and
the top of `ps` before every run; nothing else running on the machine
(Robert's rule, and the orphan of 17 Sep).

## Write scope

A new worktree `../mo-lang-erosion4-control` from `erosion4-mo` with one
commit per variant on a branch `erosion4-control` (never merged): variant
`cheap` (the third `ensures` replaced by
`ensures looks_due?(result.board, now) or !looks_due?(result.board, now)`, a
call on the board that does not walk finished jobs, in a whole statement), and
variant `none` (the third `ensures` deleted). Nothing in `main`'s tree. The
outputs under `audit/evidence/2026-09-18/gen4-memory-control/` (the run logs
as printed with the date and `uptime` at their head, the diffs of both
variants, the scripts used).

## Parts

A. Build the two variants with the same `mo` (`toolchain/zig-out/bin/mo` on
`main` at the commit named in the log) and rebuild generations three and four
with it too, so all four binaries come from one compiler. Confirm each
variant's `mo check` is green and `mo test` on `board.mo` passes (a variant
whose tests fail is not a control).

B. Run `measure.py` (30,000 jobs, `MO_CORES=1`, as the speed probe did) on
each of: gen 3, gen 4, cheap, none, each with contracts on and with
`MO_CONTRACTS=0`: eight runs, each twice, the second run's numbers on the page
beside the first's. Record the RSS after creates, the RSS after pairs, pairs
a second, and `restart`.

C. One `perf record` of the cheap variant's pairs phase, contracts on, and the
`/slowest` surface for it, as the speed probe did, so the reader can see
whether `mo_disown_in` is still on the profile.

## Numbers

The eight-cell table (variant × contracts), two trials each, load average
beside each; a one-paragraph reading of which of H1, H2, H3 the numbers
support, written by the worker as a claim for the lead to read.

## Done when

The table with sixteen rows on
`audit/evidence/2026-09-18/gen4-memory-control/RESULTS.md`, every raw log
beside it with the date and `uptime` at its head, the two variant diffs, the
branch `erosion4-control` pushed, no `jobq` process left (`pgrep -x jobq`
empty), and a report with the numbers and a numbered list "Decisions the
brief did not cover".

## Related

- [[erosion-round]]
- [[decision-log]]
- [[the-audit-workflow]]
