# The generation-four memory control probe: results

Run 18 Sep 2026, 07:57 to 08:33 UTC (3:57 to 4:33 AM ET), on the exe.dev VM (4 cores), by the Opus worker, against the
pre-registered page `mo-wiki/plans/gen4-memory-control-probe.md` (not edited).

**Compiler.** Every binary comes from `toolchain/zig-out/bin/mo` on `main` at **972c872** (sha256 `26d92b56...`; `zig build`
at 972c872 found it current). The four `jobq` binaries and their sha256 are in `scripts/build.sh`.

**Programs.** gen3 = branch `erosion3-mo` at ca550e5; gen4 = `erosion4-mo` at 3625392; cheap = `erosion4-control` at
8358bb2; none = `erosion4-control` at 5cbd3eb (pushed, not merged). The variants change only sweep's third `ensures`,
`examples/programs/jobq/board.mo` line 383 (`variant-cheap.diff`, `variant-none.diff`; the rest of each diff is
`.mo.ids` hash records). Every jobq file's `mo check` is green on both variants; `mo test` passes 28/28 on `board.mo`,
and the `verified:` lines on `queue.mo` and `server.mo` keep erosion4-mo's sim counts (100 runs).

**Method.** `scripts/measure.py` (byte-identical to the speed probe's) at 30,000 jobs, `MO_CORES=1`, `TRIES_FIELD=max_tries`,
contracts on and `MO_CONTRACTS=0`; `scripts/run.sh` runs the eight cells in order, trial 1 of all eight, then trial 2, up to
trial 5, one process at a time, 3 s apart. Each log opens with the date, `uptime` and the top of `ps`. Every jobq ran under
`timeout --foreground 240`, inside `timeout 300` on `measure.py`, with `scripts/watchdog.py` killing any `jobq` over 4 GiB
RSS (it never fired). No `jobq` was left after any run or at the end (`pgrep -x jobq` empty).

## The sixteen rows (trials 1 and 2, the page's table)

The load average is the 1-minute figure at the head of each log; it carries over from the run before (3 s gap), so a
figure near 3 is the previous measurement itself, not another process (see "Load", below).

| variant | contracts | trial | time (UTC) | load 1-min | RSS after creates (MiB) | RSS after pairs (MiB) | pairs/s, 32 workers | pairs/s, 1 worker | restart (s) |
|---|---|---|---|---|---|---|---|---|---|
| gen3 | on | 1 | 08:07:20 | 2.07 | 146.2 | 166.5 | 1893 | 299 | 1.03 |
| gen3 | on | 2 | 08:12:07 | 3.12 | 156.4 | 186.3 | 2039 | 262 | 0.99 |
| gen3 | off | 1 | 08:07:56 | 2.56 | 145.2 | 194.8 | 1932 | 342 | 1.02 |
| gen3 | off | 2 | 08:12:43 | 3.08 | 144.9 | 233.1 | 1908 | 316 | 0.95 |
| gen4 | on | 1 | 08:08:32 | 2.75 | 143.4 | 161.0 | 565 | 227 | 1.05 |
| gen4 | on | 2 | 08:13:19 | 4.02 | 129.6 | 147.7 | 542 | 261 | 1.10 |
| gen4 | off | 1 | 08:09:08 | 2.39 | 42.9 | 95.0 | 1995 | 325 | 1.29 |
| gen4 | off | 2 | 08:13:55 | 3.34 | 38.0 | 80.3 | 1703 | 356 | 1.33 |
| cheap | on | 1 | 08:09:44 | 2.66 | 58.5 | 91.0 | 1975 | 336 | 1.38 |
| cheap | on | 2 | 08:14:31 | 2.72 | 143.4 | 163.4 | 1834 | 301 | 1.20 |
| cheap | off | 1 | 08:10:20 | 2.58 | 131.2 | 148.6 | 1845 | 320 | 1.23 |
| cheap | off | 2 | 08:15:07 | 2.69 | 34.2 | 125.4 | 1858 | 305 | 1.35 |
| none | on | 1 | 08:10:56 | 2.32 | 97.6 | 126.8 | 1944 | 322 | 1.34 |
| none | on | 2 | 08:15:44 | 2.83 | 117.6 | 135.2 | 1855 | 316 | 1.46 |
| none | off | 1 | 08:11:32 | 2.41 | 127.7 | 152.4 | 1846 | 332 | 1.37 |
| none | off | 2 | 08:16:22 | 2.78 | 127.4 | 174.5 | 1868 | 285 | 1.30 |

## All five trials

The page asked for two; three more were run because the first sixteen (set A, below) showed RSS moving by 70 MiB between
two trials of one cell. "Low-state" counts runs whose RSS after the creates is under 90 MiB.

| variant | contracts | RSS after creates, trials 1-5 (MiB) | RSS after pairs, trials 1-5 (MiB) | median after pairs | low-state runs (after creates < 90 MiB) | pairs/s at 32, trials 1-5 | median pairs/s | median restart (s) |
|---|---|---|---|---|---|---|---|---|
| gen3 | on | 146, 156, 161, 163, 148 | 166, 186, 196, 186, 164 | 186 | 0/5 | 1893, 2039, 1819, 1935, 1795 | 1893 | 1.03 |
| gen3 | off | 145, 145, 154, 139, 156 | 195, 233, 245, 234, 195 | 233 | 0/5 | 1932, 1908, 1687, 1857, 1818 | 1857 | 0.98 |
| gen4 | on | 143, 130, 121, 123, 120 | 161, 148, 141, 127, 156 | 148 | 0/5 | 565, 542, 547, 531, 546 | 546 | 1.10 |
| gen4 | off | 43, 38, 33, 133, 120 | 95, 80, 80, 148, 162 | 95 | 3/5 | 1995, 1703, 2024, 1895, 2033 | 1995 | 1.33 |
| cheap | on | 58, 143, 82, 132, 33 | 91, 163, 95, 171, 65 | 95 | 3/5 | 1975, 1834, 1749, 1906, 1797 | 1834 | 1.32 |
| cheap | off | 131, 34, 136, 128, 78 | 149, 125, 153, 158, 102 | 149 | 2/5 | 1845, 1858, 1848, 1891, 1863 | 1858 | 1.23 |
| none | on | 98, 118, 125, 129, 53 | 127, 135, 150, 159, 69 | 135 | 1/5 | 1944, 1855, 1812, 1906, 2048 | 1906 | 1.34 |
| none | off | 128, 127, 121, 94, 132 | 152, 174, 184, 115, 175 | 174 | 0/5 | 1846, 1868, 2061, 1814, 1888 | 1868 | 1.35 |

## Set A: the first sixteen runs, restart column invalid

The first batch (07:57 to 08:06 UTC, `scripts/run-setA.sh`, logs under `logs/setA-restart-invalid/`) wrapped jobq in plain
`timeout 240`. GNU `timeout` moves itself to its own process group, so `measure.py`'s SIGTERM to the group before the
restart missed jobq: the old server kept the port and answered the "restart" (0.00 s, 3 MiB; each log ends with the two
jobq pids left). The RSS and rate columns were taken before that point and are sound; the leftover servers were killed
after each run and were idle during the next. Only the restart column is invalid, and it is not shown.

Set A (restart invalid), trials 1-2:
| variant | contracts | RSS after creates (MiB) | RSS after pairs (MiB) | pairs/s at 32 |
|---|---|---|---|---|
| gen3 | on | 143.4, 147.3 | 220.3, 232.2 | 1871, 2010 |
| gen3 | off | 150.6, 146.0 | 206.7, 234.8 | 1835, 1762 |
| gen4 | on | 35.9, 113.9 | 56.3, 128.6 | 572, 556 |
| gen4 | off | 114.3, 116.2 | 165.0, 148.0 | 1734, 1961 |
| cheap | on | 121.0, 133.7 | 169.1, 166.2 | 1861, 2068 |
| cheap | off | 42.7, 97.3 | 60.3, 128.6 | 1929, 1992 |
| none | on | 115.9, 118.2 | 136.6, 163.5 | 1826, 1542 |
| none | off | 110.6, 134.3 | 164.1, 189.9 | 1792, 1921 |


## Part C: the cheap variant, contracts on

`logs/perf-cheap.log` (perf record -F 499 -g, the whole `measure.py` run): 1,208 pairs a second at 32 workers under perf,
RSS 129 MiB after the pairs. The flat profile: `copy_slice` 5.98 %, `ptab_drop` 4.38 %, `copy_out` 3.86 %, `mark_value`
2.44 %, `memcpy` 2.38 %, **`mo_disown_in` 1.73 %** (23 % in generation four on 17 Sep). The profile has generation three's
shape: `ptab_drop` under `mo_compact` and the copy pair lead.

`logs/surface-cheap.measure` and `logs/surface-cheap.slowest` (the surface build, `/slowest?n=10` and `/memory` every 4 s):
1,878 pairs a second, RSS 148 MiB after creates and 175 after pairs. `/memory` has `resident_bytes` 67 MB to 190 MB over
the run while `region_bytes` stays 9.9 MB to 32 MB: the region is a small part of the resident set.

## Load

`logs/load-sampling.log`: 80 samples of every thread in state R or D, 08:14:37 to 08:15:18 UTC, in the middle of the batch
(the lead saw 3.1 at 08:14). A `ps` taken right after it, at 08:15:18 (in the worker's shell, not in the log), showed one `measure.py` and one `jobq` (the cheap variant, trial 2); only `measure.py` and `jobq` appear among the sampled threads beside the kernel's journal, the two `claude` sessions, the watchdog, and an `mi-scavenger` thread (0.10; a mimalloc thread, so not jobq's, whose allocator is Zig's `SmpAllocator` in the profile; most likely a `claude` session's). The means: the
client's main Python thread 1.00 runnable; jobq 0.44 runnable and 0.38 in D (the log's fsync); `jbd2/vda-8`, the ext4
journal, 0.38 (R and D); the client's worker threads about 0.5 together; `claude` 0.10. Linux counts D-state threads in
the load, so one client, one single-core server and the journal make a load near 3 on their own.

## Reading (the worker's claim, for the lead)

The page's premise did not reproduce. Generation four with contracts on gave 127 to 161 MiB after the pairs in all five
trials here, and 56 and 129 in set A: the 46 MiB of 17 Sep is one draw from a spread. The low-RSS state (roughly 33 to 60 MiB
after the creates) appears intermittently in every generation-four-family cell, with contracts on and off, in `cheap` and in
`none` (gen4 off 3/5, cheap on 3/5, cheap off 2/5, none on 1/5; gen4 on 1/2 in set A), and never in generation three
(0/14). So the low RSS is not produced by the postcondition's walk (against H3), and it does not follow the compaction
point the walk sets (against H1: deleting the `ensures` does not return a steady 169). H2's specific prediction also
fails: neither `cheap` nor `none` sits near 46 with contracts on; they sit where gen4 sits, a spread with medians 95 and
135. What the numbers support is a weaker form of H2: something in generation four's code, not the contract, makes a
low-memory state possible, and whether a run lands in it is not controlled here (the surface's `/memory` suggests it is in
what the allocator gives back outside the region, but this probe did not test that). The rate half is clear: `cheap`
(median 1,834) and `none` (1,906) run at generation three's rate (1,893) and generation four's 546 is the walk
(`mo_disown_in` 23 % to 1.7 %). Fable's rate prediction (1,300 to 1,700) was low because the VM had four cores this time,
not three; the RSS predictions (cheap 40 to 60, none 150 to 180) held in 1 and 2 of 5 trials respectively.

## Files

- `logs/<variant>-contracts-<on|off>-trial<1..5>.log`: the forty runs, each as printed.
- `logs/setA-restart-invalid/`: the first sixteen runs.
- `logs/perf-cheap.log`, `logs/surface-cheap.measure`, `logs/surface-cheap.slowest`, `logs/load-sampling.log`.
- `variant-cheap.diff`, `variant-none.diff`: `git diff 3625392 8358bb2` and `git diff 3625392 5cbd3eb`.
- `scripts/`: `build.sh` (part A's commands, collected after they were run), `run.sh`, `run-setA.sh`, `partc.sh`,
  `watchdog.py`, `measure.py`, `tabulate.py` (`python3 scripts/tabulate.py logs` prints the tables above).
