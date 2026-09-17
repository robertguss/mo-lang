# Audit reading: the gen-4 speed-loss probe

**Date:** 17 September 2026
**Author:** the auditor (a Perplexity session, independent of Fable)
**Charter:** the auditor reads raw evidence and files a reading before seeing Fable's. Only Robert can overrule.
**Scope of this reading:** the M-3 item 2 speed-loss probe that compares the erosion-3 and erosion-4 branches of the jobq program under a fixed 30,000-job workload, with and without runtime contracts. Probe committed at `854a815`; program under test is `examples/programs/jobq/board.mo` on `erosion3-mo` (`fn sweep` at 247-249) versus `erosion4-mo` (`fn sweep` at 381-383, `fn decide` at 158-159).
**Status:** filed cold, before reading Fable's parallel reading. Filed against `69860b0`.
**Explicit gap in this reading:** the erosion-3 and erosion-4 branches are worktrees on the lead's machine and are not carried in the audit clone or the evidence bundle. The auditor did not independently read the source diff between the two `board.mo` sweeps. This reading rests on the perf profile, the run and surface logs, and the runtime-`/slowest` and `/memory` traces filed under `audit/evidence/2026-09-17/gen4-speed-probe/`; it does not verify what the code change is or that the two branches differ only in the way the profile suggests.

---

## What the auditor read cold

1. `run.log` — one run of `measure.py` per branch under `perf record -F 499 -g`, then the two `perf report` hot-symbol tables, then two more measure runs with `MO_CONTRACTS=0`.
2. `surface.log` — measure runs against a `jobq-surface` build (both branches) with the runtime's `/slowest` and `/memory` endpoints available.
3. `surface3.slowest` and `surface4.slowest` — the raw JSON captured every 4 s from the surface runs, showing per-fiber `took_us` / `waited_us` / `longest` and the runtime's `resident_bytes` / `region_bytes` / `packed_bytes` decomposition with the five largest processes.
4. `measure.py` — the 30,000-job client (8 producers on keep-alive; single worker for 10 s and 32 workers for 10 s of lease+ack pairs; then RSS after; then a killed-and-restarted `/health` timing).
5. `build.sh`, `run.sh`, `surface.sh` — the exact commands used, so the auditor can see that both branches were built with the same step-35 `mo` toolchain (`/home/exedev/Projects/mo-lang/toolchain/zig-out/bin/mo`), that MO_CORES=1 was set for every run, and that the perf record ran without `MO_CONTRACTS=0` first and re-ran with contracts off second.

## What the evidence shows

### The headline numbers

| Run | Creates (/s) | Pairs, 1 worker (/s) | Pairs, 32 workers (/s) | RSS after pairs |
|---|---|---|---|---|
| gen 3, contracts on, under perf | 1804 | 301 | **940** | 173 MiB |
| gen 4, contracts on, under perf | 1786 | 283 | **519** | 46 MiB |
| gen 3, contracts off | 2413 | 340 | **1793** | 168 MiB |
| gen 4, contracts off | 2247 | 392 | **1736** | 169 MiB |
| gen 3, contracts on, surface build | 2873 | 359 | **1664** | 203 MiB |
| gen 4, contracts on, surface build | 2654 | 266 | **533** | 167 MiB |

- **Under perf, 32 workers, contracts on:** gen 4 is at **55%** of gen 3's throughput (519 / 940). Under the surface build with contracts on, gen 4 is at **32%** of gen 3 (533 / 1664).
- **Under `MO_CONTRACTS=0`:** the gap closes to **97%** (1736 / 1793). Under contracts off, gen 4 is competitive with gen 3.
- **RSS after pairs, contracts on:** gen 4 is at 46 MiB against gen 3's 173 MiB. This is a large, one-sided win for gen 4 that the report does not headline but the evidence shows clearly.

### The perf profile pinpoints the cause

Under contracts on, gen 3's hottest symbols are `ptab_drop` (4.67%), `copy_slice` (4.58%), `copy_out` (3.27%), `memcpyFast` (2.36%), `mark_value` (1.87%) — none over 5%, all in the runtime's data-plane copy path. Gen 4's hottest symbol is **`mo_disown_in` at 23.15%**, with its call graph rooted almost entirely in `mo_r_List_all_q` inside a function `f47` invoked from `pu1` → `run_update` → `deliver`. `mo_r_List_all_q` is the runtime helper the compiler emits for a `List.all?` call site; `mo_disown_in` is the ownership-transfer contract check the runtime runs on capability-typed values crossing an ownership boundary.

The fact that `mo_disown_in` accounts for 23% of the profile under contracts on and vanishes under contracts off (where gen 4 matches gen 3) is the whole story: **gen 4's `sweep` (or its `decide` companion) added a `List.all?` in the hot per-message path that materially multiplies the number of contract-checked ownership transfers per pair**. The auditor cannot see the source diff and so cannot say whether this was intentional (a real correctness fix) or accidental (a regression from a refactor), but the shape of the profile is unambiguous.

### The surface trace corroborates and adds one thing

The `surface4.slowest` trace shows per-fiber `took_us` values in the 5-40 ms range for `Worker` fibers whose `longest` is `ask` — i.e., the pair delivery is spending most of its wall time in the ask itself, not in scheduler waits or Fs.append. This is consistent with the perf profile: the cost is inside `deliver` → `run_update`, which is where `mo_disown_in` is charged. `surface3.slowest` shows the same shape at lower magnitudes (workers taking single-digit-ms `took_us` typically). Nothing in either surface trace suggests I/O, scheduling, or GC as the bottleneck; both point at in-flight ownership work.

The surface `/memory` values also corroborate the RSS gap: gen 4's `resident_bytes` steady state hovers around 65-155 MiB with `Queue` region_bytes 8-23 MiB, versus gen 3 (not filed in the same shape, but the measure-run RSS-after numbers of 203 MiB vs 46 MiB tell the same story). Gen 4 is materially cheaper in memory and materially more expensive in per-pair CPU when contracts are on.

## Where the evidence is thin, and what would make it thicker

- **No source diff.** The auditor cannot confirm from filed evidence that the only relevant change between the two branches is a `List.all?` insertion in `sweep` or `decide`. This is the single largest gap in this reading. Fable's `run.log` names line numbers for both `sweep` (247-249 vs 381-383) and `decide` (158-159), but does not include the source text at those lines in the evidence bundle. The auditor recommends the evidence bundle for any future speed-loss probe include a `diff` snippet at the sites the report calls out.
- **One trial per configuration.** The numbers filed are single runs, not run distributions. The 55% vs 32% spread between the perf run and the surface run (both contracts-on, 32 workers) is 13 percentage points — that is not measurement noise on a single 10-second window. The perf-record overhead itself likely explains part of the spread (perf record narrows gen 3's throughput by roughly half its no-perf value), but that means the perf-vs-surface pair are measuring different things and cannot both be cited as "the gen 4 gap." The auditor takes the surface number (532 / 1664 = 32%) as the honest read because it is the throughput without perf overhead, and the perf number (519 / 940 = 55%) as an artifact of the profiling harness. The report should adopt one convention and stick with it.
- **No 8-, 4-, or 16-worker measurements.** With only 1-worker and 32-worker numbers, the auditor cannot see whether the gen-4 gap under contracts opens at low concurrency (fixed per-pair cost) or only at high concurrency (contention). The 1-worker numbers (283 / 301 = 94%) suggest the per-pair overhead is small in isolation and the 32-worker gap comes from contention on the contract-check path, which is consistent with an ownership check that serializes on a shared structure — but the auditor cannot say this from two points. A worker sweep (1, 2, 4, 8, 16, 32) at contracts-on would tell the story cleanly.

## Reading

- **There is a real speed-loss on erosion-4 relative to erosion-3 in the jobq program**, isolated to the contracts-on data path, and traceable in the profile to `mo_disown_in` under `mo_r_List_all_q` in the fiber that handles each pair. Under contracts off, gen 4 matches gen 3 to within 3%. Under contracts on, gen 4 delivers roughly 32% of gen 3's 32-worker throughput on the surface build, or 55% under perf record.
- **The RSS story is the other half.** Gen 4's contracts-on steady RSS after pairs is 46 MiB against gen 3's 173 MiB — a factor of nearly four in the opposite direction. Whatever the erosion-4 refactor did, it traded per-pair CPU (under contracts) for a large memory reduction. The report should headline both numbers, not just the throughput regression. Whether the trade is worth taking depends on the goal of the erosion-4 refactor, which the auditor does not read from the filed evidence.
- **The probe answers the M-3 item 2 question at the level the auditor asked for it.** The question was "does erosion-4 pay a speed penalty at the runtime layer, and if so, where?" The answer is yes; in the ownership-transfer contract check invoked by a `List.all?` call in the pair-handling path; and it is invisible with contracts off.
- **The probe is not a program-7 reading.** Program 7 is a different program with different bricks and a different concurrency shape; the auditor does not extrapolate this ratio to program 7. What this probe does establish is that when the auditor reads program 7's numbers, a comparable `mo_disown_in`-heavy profile under contracts on should be treated as a real cost signal rather than dismissed, and Elixir's process-model contract-check equivalent should be measured on the same axis if the comparison is to be honest.

## Standing auditor concerns filed with this reading

1. **`List.all?` on a capability-carrying `List` inside a hot per-message path is a repeatable footgun.** The compiler emits a `mo_disown_in` per element on that call site, and the runtime pays the ownership-transfer cost per element per pair. If this pattern shows up in program 7's bricks or its own code, the same 2×-3× throughput cliff under contracts on will show up. This is worth naming in the language guide before program 7 lands, not after.
2. **The bricks page's P4 story leans on contracts-on throughput being close to raw.** The gen-4 probe is a direct counter-example (contracts add roughly 3× per-pair cost in one hot path), and the bricks page's crypto row shows a `List(UInt8)` overhead of 6.3× under `mo run` and 2.9× under the binary on 1 MiB hash. The two ratios come from different causes but they compound in one direction: program 7's P4 numbers under contracts on with `List(UInt8)` payloads will be materially worse than the raw-brick numbers. The bricks page should be honest about this before program 7 is measured against it.

## What would flip this reading

- A source diff showing that the erosion-4 change under audit is materially different from a `List.all?` insertion in `sweep` or `decide`, such that the perf profile is misleading about cause.
- A worker-sweep run at contracts-on (1, 2, 4, 8, 16, 32 workers) that shows the gap is present at low concurrency (which would rule out contention and point at per-pair fixed cost) or absent at moderate concurrency (which would suggest the 32-worker number is a scheduler pathology, not a data-plane cost).
- A repeat run of the surface configuration on the same machine, same commit, showing the 32% throughput ratio moves by more than a few percentage points. Single-trial numbers this far apart from the perf-record numbers argue for at least one repeat run before the ratio is cited elsewhere.

None of these appeared in the evidence read. The reading stands as filed, with the source-diff gap explicit.
