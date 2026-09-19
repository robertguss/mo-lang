# Worker verification evidence

Worker: GPT-6-Astra, `mo-executor`, Herdr worker `w4:pN`; owned run pane `w4:pQ`.
Base: `91898b542495e69a55ea9b993c9eb75611ae0b7d`.
Branch: `harness/executor-foundation-r01`.
Only `toolchain/harness/executor/` was written. No push, compiler build,
benchmark, lead auditor inbox, or shared Mac Docker endpoint operation occurred.

## Final commands and actual exits

These commands ran from the worktree root in the owned Herdr run pane. Each log
has a sibling `.exit` file containing the shell's captured real exit code.

```sh
python3 toolchain/bench/step36/guard.py 60 -- python3 -B toolchain/harness/executor/test_executor.py
python3 toolchain/bench/step36/guard.py 600 -- python3 -B toolchain/harness/executor/selftest.py toolchain/harness/executor/evidence/live-05
python3 toolchain/bench/step36/guard.py 30 -- python3 -B toolchain/harness/executor/evidence/final_check.py
```

| Final output | Result |
| --- | --- |
| `unit-03.txt` | exit 0; 9 unit tests |
| `live-05.txt`, `live-05/summary.json` | exit 0; 17/17 live controls; 35 declared checks across cases |
| `final-state.txt` | exit 0; zero containers, run units, temporary run directories, or host test processes |

The live case timings total 33.881 seconds, with 412,232 artifact bytes in the
attempt at summary time. This is an execution log, not a performance comparison.
The outer log and small summary add to that amount; the whole retained evidence
bundle is below 3 MiB. Negative-control checks intentionally fail within
successful rejection controls. Do not interpret the 35 inventory entries as
35 successful candidate assertions.

The controller-death case records actual controller return code **-9**. The
supervisor kill command returned **0**; its missing terminal observation yields
`infrastructure_failure`, not fabricated candidate exit information. Deadline,
cancel and overflow fixture exits are **137**, and the deliberate nonzero
fixture is **7**. Independent post-deadline snapshots precede any recovery
collection. Cgroup existence while running and absence afterward use the real
`/mo.slice/mo-executor.slice/` hierarchy.

`live-05/sources/` captures the exact Python sources used in the final live
attempt. Per-case `manifest.json`, `result.json`, stdout/stderr bytes, running
snapshots, and cleanup snapshots retain raw identity/policy/check evidence.
The adapter stores source digests in each manifest.

## Retained attempts (never relabeled)

| Attempt | Actual exit and interpretation |
| --- | --- |
| `environment.txt` | 0; Python/Docker/parent-slice prerequisite observations |
| `unit-01.txt` | 0; initial 4 unit tests |
| `smoke-01.txt`, `smoke-01/` | 1; effective policy rejected absent PATH before candidate start |
| `smoke-02.txt`, `smoke-02/` | 0; explicit fixed PATH; positive fixture; its effective record is the unit policy baseline |
| `live-01.txt`, `live-01/` | 1; 9/16 controls; attach pipe drain defect, erroneous five-process assertion, short-lived PID probe |
| `live-02.txt`, `live-02/` | 1; 11/16 controls; overflow/PID repaired; erroneous five-process assumption remained |
| `live-03.txt`, `live-03/` | 0; 17/17 as printed, **superseded** because review found an incorrect fallback cgroup path |
| `unit-02.txt`, `live-04.txt`, `live-04/` | 0 and 0; 9 unit tests and 17/17 controls with corrected cgroup proof |
| `unit-03.txt`, `live-05.txt`, `live-05/` | 0 and 0; final source, additionally rejects disposal of an active deadline reaper |

The descendant assertion was replaced with stronger PID/PPID/session topology,
not relaxed to a smaller arbitrary process count. BusyBox's recorded processes
already included the parent, child, grandchild and independent session. The PID
probe now keeps its parent alive after the child hits the limit, making the
kernel event observable. Output overflow now drains/discards bounded buffered
output after killing the candidate so the Docker attach client cannot deadlock.

## Decisions and limits for lead acceptance

1. The first slice is a trusted-caller synthetic fixture API. No provider or Mo
   integration and no arbitrary host file copy interface were added.
2. Execution deadline is registration-relative, default 10 seconds. The separate
   deadline timer allows a two-second grace and then performs bounded cleanup.
   Fast completion and every forced-stop outcome remove the container and all
   descendants, including separate sessions.
3. Cleanup uncertainty fails closed and requests only the dedicated machine's
   shutdown. These shutdown branches are mocked in unit tests; the live machine
   was not deliberately made unreachable or shut down.
4. Docker exposes an exit code, not an unambiguous termination signal. The
   authoritative `signal` stays null; a separate `signal_hint` is explicitly
   conventional. Supervisor death does not invent an exit code.
5. The machine's before/after container inventory is unchanged, and final
   resources/processes are absent. The **Mac shared Docker inventory was not
   observed** because the worker was forbidden to touch that endpoint. The lead
   retains that comparison and independent integrated-tree acceptance.
6. This is no kernel/runtime-exploit, whole-machine-failure, compiler/runtime,
   provider, Step 39, Darwin full-sync, Program 7, or benchmark acceptance.

Source/README staged whitespace validation returned 0. Full staged
`git diff --cached --check` returned 2 solely for the captured environment log's
blank final line (`environment.txt:119`); the raw log was preserved unchanged.
