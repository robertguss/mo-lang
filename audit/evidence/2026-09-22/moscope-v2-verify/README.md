# Moscope v2 and two toolchain fixes, independent Darwin verification — 22 Sep 2026, 3:30–4:00 PM ET

Scope: the three commits of branch `moscope/real-data-v2` on main 9652f16c:
455ba3eb (native `Json.decode` use-after-free), bc185743 (moscope v2), eff64c56
(`mo run` gives Server and Vm `std.heap.smp_allocator` instead of the process
arena). Verified by a Claude Code session (Opus 5.5) at Robert's request, on his
Mac (14 cores, Darwin 25.6, Zig 0.16.0). No Linux replay, no Oracle review, no
auditor reading. The author of the commits was an earlier Claude Code session
the same day; this verification re-ran everything itself.

Candidate eff64c56d9198ff7734c0b19d3ce59d998734903, tree
8f6d288371d0717d492ca0e387b87eae162c87bb, fast-forwarded onto main unchanged.
Worktrees (session scratchpad, since removed except `verify`): `verify` = branch
lead/verify-moscope-v2 at the candidate; `base` = main 9652f16c; `redalloc` =
the candidate with only `toolchain/src/main.zig` swapped for red checks and
DebugAllocator runs. Every `zig`, `mo` and test process ran under
`toolchain/bench/step36/guard.py`.

## Files

- `logs/*.log`, `logs/*.exit`: raw output and the guard's exit for each run
  named below; `logs/modules/`: moscope's nine modules, interpreter and native.
- `logs/verification-only-patches.diff`: the two scratch-only patches
  (DebugAllocator in place of smp_allocator; a guard line printing why it
  returns 125). Never committed.
- `logs/real-aggregates/`: real-history exits, load averages and the
  best-of-five timing table. No transcript text, paths or excerpts were kept;
  the history snapshot and every stdout/stderr from it were deleted after
  aggregation.
- `probe/probe.mo`, `probe/gen.py`: the JSON differential probe and its
  generator; `python3 gen.py 7 400` regenerates the 404 documents (sha256 in
  `probe/docs-seed7-n400.sha256`).

## Commands and printed results

| run (log)                                                                                                              | printed result                                                                                                                                      |
| ---------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| `zig build --summary all`, candidate / main (`verify-build`, `base-build`)                                             | exit 0 / exit 0                                                                                                                                     |
| `zig build test-corpus --summary all`, candidate, alone (`verify-test-corpus`, 15:40:42–15:43:58 ET, load 4.79)        | exit 0, "5/5 steps succeeded; 277/277 tests passed"                                                                                                 |
| same, first attempt while other checks ran (`verify-test-corpus-run1-concurrent`)                                      | exit 1, 275/277: fs_scope step 40 and exec_controls step 41, each a guard 125 on correct payload output                                             |
| `mo build --tests stdlib/json.mo`, run, old runtime (`json-old-run`)                                                   | exit 139, no output                                                                                                                                 |
| same, fixed runtime (`json-new-run`)                                                                                   | exit 0, "7 passed, 0 failed"                                                                                                                        |
| `test-corpus -Dtest-filter="decoding the same JSON fifty times"`, candidate with main's main.zig (`redalloc-filtered`) | exit 1, the `mo run` assertion failed                                                                                                               |
| same, candidate (`green-alloc-filtered`)                                                                               | exit 0, 2/2                                                                                                                                         |
| `check.py --mo`, `check.py --native` (`check-interp`, `check-native`)                                                  | 34 passed / 34 passed, exit 0 each                                                                                                                  |
| moscope modules, `mo test` and `mo build --tests` (`modules/`)                                                         | 40 tests in each runtime, all pass; `find` native build drew one guard 125, three clean reruns                                                      |
| test-corpus, DebugAllocator under `mo run` (`debugalloc-test-corpus-run1`)                                             | exit 1, 276/277: guard 125 on fs_scope step 40's native test binary                                                                                 |
| same, guard instrumented (`debugalloc-test-corpus`)                                                                    | exit 0, 277/277; no 125 occurred                                                                                                                    |
| probe, 404 documents: interpreter, fixed native, old native                                                            | exit 0 / 0 / 139; interpreter and fixed native byte-identical; 0 semantic mismatches against Python `json`; only the truncated document is an error |

Real history, a copy-on-write snapshot of `~/.claude/projects` (601 MB, 352
JSONL files), query `zig build`, load average 2.9–4.3:

| run                                             | exit | result                                                    | time          | peak RSS    |
| ----------------------------------------------- | ---- | --------------------------------------------------------- | ------------- | ----------- |
| native                                          | 0    | 141 matching messages; 141 of 141 excerpts hold the query | 3.27 s        | 14.1 MiB    |
| native, absent query                            | 1    | none                                                      | 3.07 s        | 14.1 MiB    |
| interpreter, candidate, best/median of 5        | 0    | stdout identical to native                                | 8.18 / 8.20 s | 24.5 MiB    |
| interpreter, main's allocator, best/median of 5 | 0    | identical stdout                                          | 7.58 / 7.60 s | 1,381.4 MiB |

## Open items

- A guard exit 125 on fs_scope step 40's native test binary appeared in two of
  four full corpus runs, once with no concurrent work. The payload's output
  passed each time, and the step is untouched by these commits. It did not
  reproduce in 150 guarded `/usr/bin/true` runs or in the instrumented rerun.
  Cause unknown; whether main shows it too was not tested.
- The allocator change costs about 8% interpreter time on this workload for 56×
  less peak memory.
- `resume:` quoting is injection-safe; a cwd of `-` or `-P` passes bare and `cd`
  reads it as an option (`cd --` would close it).
