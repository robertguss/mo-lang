# Lifecycle correction after lead review

Parent implementation commit: `dfed32f9eaf3de090aef79510e3573b3f03bdc15`.
Worker: GPT-6-Astra, `mo-executor`, worker pane `w4:pN`, owned run pane `w4:p11`.
All earlier attempts remain unchanged. No push or global environment change.

## Corrected ordering

`Run.collect()` no longer issues the unconditional stop of the supervisor,
deadline timer, and deadline service. The machine-local `finalize()` now:

1. Acquires the registration lock shared with bootstrap. The deadline reaper
   deliberately does **not** acquire this lock and cannot be blocked by it.
2. Stops only the supervisor and confirms no active/activating/deactivating
   supervisor can still create candidate writers.
3. Resolves the actual container/cgroup identity from registration (or the
   daemon if registration was interrupted), removes the container, successfully
   queries daemon absence, and checks the actual cgroup is absent.
4. Persists `cleanup-confirmed.json` **before** disarming anything independent.
   Any failure through this point leaves the timer/service untouched; the host
   requests only the dedicated machine's shutdown as before.
5. Stops the deadline timer/service, then separately confirms all run units
   are absent. The host result records this order and only then can pass.

Thus a disappearing controller before proof leaves the independent reaper;
a disappearing controller after disarm cannot leave candidate writers alive.
An active reaper can only be stopped after positive candidate/cgroup proof.

## Related interleavings inspected

- Host start/collect/dispose use a per-run file lock. A start claim persists
  before dispatch and is one-shot even when its reply is lost. Collect/dispose
  close future starts. Failed dispatch needs collection, not replay.
- Machine bootstrap/finalize/dispose share the existing registration lock.
  Finalization cannot overtake bootstrap and then allow a late supervisor.
  Bootstrap also rejects expiration before supervisor dispatch.
- Disposal requires persisted cleanup proof and fresh container/unit/cgroup
  absence. It cannot remove a live reaper's files. Confirmed disposal is
  idempotent; later collection rejects locally instead of attempting machine
  shutdown because the remote files were deliberately removed.
- Cancellation stays available while collection holds the lifecycle lock; it
  only writes the cancellation request and never disarms deadline cleanup.
- An uncertain RPC completion remains fail-closed. No general retry, lease,
  server, provider, or plugin framework was introduced.

## Focused live fault control

`test_lifecycle_live.py` changes only its own transient supervisor's
`ExecStopPost` to `/usr/bin/false`. Its systemd journal records actual exit
**1/FAILURE**. An incomplete terminal observation enters the ordinary
post-observation collection path; a process-local test patch makes explicit
cleanup return uncertainty. The independent reaper's implementation is untouched.

Before collector death the raw snapshot proves the candidate/container and
actual cgroup still exist, the deadline timer is **active**, no cleanup proof
exists, and no final host verdict exists. The test then kills the collector
(actual return **-9**) before its host machine-stop fallback is dispatched.
After the independent deadline, and **before recovery collection**, it observes
no container, no run units, no original cgroup, and the independent reaper's
`absent: true` / `cgroup_absent: true` record. Recovery returns
`infrastructure_failure`, never a fabricated successful candidate verdict.

Final focused proof: `lifecycle-live-04/uncertain-before-death.json`,
`supervisor-journal.txt`, `collector-kill.json`, `independent-after.json`,
`reaped.json`, and `collector-gap/result.json`. Source snapshots and the exact
injected bootstrap/finalizer code are retained in the same attempt directory.
No live machine shutdown was needed or performed.

## Commands and exits

All ran from the worktree root in the owned Herdr run pane. Shell exit codes
are retained in matching `.exit` files.

```sh
python3 toolchain/bench/step36/guard.py 60 -- python3 -B toolchain/harness/executor/test_executor.py
python3 toolchain/bench/step36/guard.py 600 -- python3 -B toolchain/harness/executor/selftest.py toolchain/harness/executor/evidence/live-07
python3 toolchain/bench/step36/guard.py 600 -- python3 -B toolchain/harness/executor/test_lifecycle_live.py toolchain/harness/executor/evidence/lifecycle-live-04
python3 toolchain/bench/step36/guard.py 30 -- python3 -B toolchain/harness/executor/evidence/final_lifecycle_check.py
```

| Output | Actual result |
| --- | --- |
| `lifecycle-unit-red.txt` | exit 1; original ordering reproduced: 10 tests, 1 failure |
| `lifecycle-unit-01.txt`, `lifecycle-unit-02.txt` | exit 0; 14 tests each |
| `lifecycle-live-01.txt` | exit 0; independent cleanup with ignored failing stop hook |
| `lifecycle-journal.txt` | exit 1; supplementary assertion expected a journal failure entry that systemd suppresses for the ignored-error hook |
| `lifecycle-live-02.txt` | exit 0; nonignored failing stop hook, including journal proof of exit 1 |
| `lifecycle-live-03.txt` | exit 0; additionally enters ordinary post-observation cleanup path |
| `live-06.txt` | exit 0; 17/17 existing fixture controls |
| `lifecycle-unit-03.txt` | exit 0; final 15 unit tests, including terminal disposal behavior |
| `live-07.txt` | exit 0; final 17/17 existing fixture controls, 35 declared checks |
| `lifecycle-live-04.txt` | exit 0; final focused fault control, collector -9, independent cleanup proven |
| `final-lifecycle-state-04.txt` | exit 0; no containers, run units, temporary run directories, or host test processes |

The final full and focused attempts each stay below the 16 MiB artifact budget.
The shared Mac Docker endpoint remains outside worker scope; lead comparison
and integrated-tree acceptance are still required. No compiler/provider or
benchmark acceptance is claimed.
