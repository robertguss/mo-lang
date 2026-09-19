# The lead's own verification runs, 19 Sep 2026

Fable lead, on the lead checkout, every command under
`toolchain/bench/step36/guard.py`. Each `<name>.exit` holds the real exit code
and `<name>.tail.txt` the last 6,000 bytes of output. Times are ET and approximate to a few minutes; the exact ones are the files' modification times.

| run | tree | when | result |
|---|---|---|---|
| `zig build` | `ddd81c06` (application workspace rebuild merged) | 8:10 AM | exit 0 |
| `zig build test --summary all` | `ddd81c06` | 8:10 to 8:18 AM | **242 of 243, exit 1**: the TLS corpus test "a fatal alert where a hello belongs is Handshake and a reset mid-hello is Closed" found `Handshake` for `Closed` |
| that test alone, five times (`-Dtest-filter`) | `ddd81c06` | 8:19 AM | 4 pass, 1 fail (`tlsflake-1..5`). Unexplained; the merged work touches no TLS or toolchain source |
| executor unit tests / application / `workspace_http/local.py` | `97202a81` (step 1 merged) | 8:43 AM | 96 OK, 25 OK, 22 OK, all exit 0 |
| `selftest.py` on `mo-executor-r01` | `97202a81` | 8:44 AM | 17 of 17, exit 0 |
| `test_lifecycle_live.py` | same | 8:45 AM | exit 0 |
| `test_workspace_live.py` | same | 8:45 AM | 22 of 22, exit 0 |
| `recovery/live.py` | same | 8:47 AM | all groups ok, exit 0 |
| `workspace_http/live.py` | same | 8:47 AM | 22 of 22, exit 0 |
| `application/controls.py` (image `sha256:b9fda4ae…`, toolchain `d31b5c5e…`) | same | 8:50 AM | 23 of 23, exit 0 |
| `workspace_http/live.py --application` | same | 8:51 AM | 22 of 22, exit 0 |
| `inventory.py` over the seven run folders | same | 8:52 AM | clean: 111 runs, 142 workspace IDs, 103 cgroups selected; 0 remaining paths, 0 slice tasks |

Later the same day, on `main` at `2a852d68` (step 2 and the raw-memory fix merged):

| run | result |
|---|---|
| all eight live suites on the restructured step 2 code (`live-rerun-step2.exits`) | first pass: application controls 22 of 23, exit 1 (`scratch-fresh`, a runner bug); after the worker's fix: 23 of 23, selftest 17 of 17, the rest unchanged and green, inventory clean |
| full suite, `test3` | **killed by the lead's own 570 s guard limit, exit 137**; no test result |
| full suite, `test4`, started while `test3`'s orphaned test binary was still alive | **243 of 244, exit 1**: two `mo build`s lost `zig-out/mo-build/.bricks/<hash>` mid-run. `guard.py` kills its child, not the group, so the orphan finished and its cleanup deleted the shared `zig-out`. Explanation, not proof |
| full suite, `test5`, no orphans, load 2.7 | **244 of 244, exit 0**, 10:37 AM ET |

Not run: the two real-machine E1 checks the step 1 worker named (the reaper
reading a populated `cgroup.events`; a stalled Docker daemon leaving
`cleanup_unconfirmed` without a power-off). Both need a fault injected on the
machine and are owed. Not run and not existing: the Mo agent against the real
workspace service on the machine, end to end.
