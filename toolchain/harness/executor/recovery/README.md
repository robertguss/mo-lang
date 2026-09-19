# Explicit workspace cleanup recovery v1

This directory adds one operator API, `recovery.recover(receipt_path,
seconds=60)`. Import it with the executor directory on `sys.path`. It cleans
only the workspace and execution identities recorded by a new `Workspace`.
It never executes/retries/resumes a candidate or file operation, rebuilds a
workspace, changes policy, or produces an application pass.

```python
from recovery import recover
result = recover('/absolute/private/results/ownership.json', seconds=60)
assert result['cleanup'] == 'confirmed'
# A lost execution outcome remains result['execution'] == 'unknown'.
```

Do this only after the original owner has gone. The original `Workspace` holds
an OS file lock for its object lifetime, including the interval between
`start_command()` and `collect()`. Successful `delete()`, object destruction,
or process death releases it. Recovery returns unresolved when that owner is
still live; it never kills the holder or steals its lock. A recovery request
closes the local ownership to further execution. There is no recovery object
constructor, background recovery loop, execution reopen API, or HTTP endpoint.

## Records and bounds

`ownership.json` is private operator data outside candidate storage. Version
`mo-workspace-ownership-v1` contains exactly:

- `run_id`, `workspace_id`: lowercase 32-hex identities.
- `selection`: exact `policy`, `image`, and `toolchain` values (null toolchain
  for the unchanged BusyBox policy).
- `directory`: canonical absolute private host result directory.
- `executions`: at most 1000 intents, each with `execution_id`, `call_id`, exact
  `execution-<id>` relative directory, Boolean `readonly`, and Boolean
  `dispatch_requested`.

The receipt precedes remote effects; the execution intent precedes reserve,
and dispatch intent precedes bootstrap. Supporting manifests are validated
without evaluating their script/source. Invalid versions, selection, identities,
record bounds, symlinks, hard links, nonprivate directories, and conflicting
local or remote binding are refused. Records are limited to 1 MiB. Identity
records are atomically replaced, with no fsync or crash-durability claim.

An exact `.owner-<workspace_id>` machine record precedes root creation; it covers
owner loss before the initial workspace state write. Ordinary delete retains
completed proofs in its retired record. Reserved, not-started authority plus
the terminal barrier and fresh runtime absence covers loss before bootstrap
transport or manifest creation. Completed IDs omitted from a receipt are a
conflict and fail before cleanup effects.

The trusted machine terminal `.recovery-<workspace_id>` lives outside the
workspace root and survives storage deletion. Registration locking serializes
create, bootstrap, and recovery; bootstrap checks the barrier *before* creating
execution storage. Recovery takes registration before workspace locks. It keeps
cleanup proof before reaper disarm, retains per-execution proof before disposal,
and verifies fresh container/unit/cgroup absence on subsequent cleanup.
Completed execution proofs also survive the ordinary complete/dispose gap in
workspace state. Only exact owned source/snapshot mounts are unmounted, never
recursively or lazily. Unknown inspection/transport/proof stays unresolved.

Each result has exact workspace/run identities, separate `cleanup` and
`execution` statuses, completed phase/identity entries, unresolved execution
identities, and a bounded error code. `confirmed` means cleanup, not execution
success. Original manifests/results/observations are not rewritten by recovery;
each host recovery attempt gets a new `recovery-<random>.json` record.

`seconds` must be finite, .5–1800 inclusive. Host lock waiting, transport, remote
registration/workspace locks and reconciliation use that attempt budget. Local
I/O, process launch, and machine failure prevent an unconditional finite
wall-time guarantee. No machine stop/reset fallback is added to recovery.

Old unjournaled workspaces are not migrated or adopted. Operator records must
be retained. Missing/conflicting proof remains unresolved; recovery does not
scan for resources to adopt or reconstruct an execution verdict. This proves
explicit cleanup after owner loss, not unattended restart, whole-machine crash
recovery, remote HTTP cancellation, or client receipt.

## Reproducible controls

Run from the repository root in an owned right/no-focus Herdr pane, using a
fresh output directory every time. The wrapper retains argv, source hashes and
snapshots, real exit, output, and local process inventory; it applies the numeric
repository guard and kills only the owned process group at exit.

```sh
python3 -B toolchain/harness/executor/recovery/run_guarded.py 120 NEW_LOCAL python3 -B toolchain/harness/executor/recovery/local_suite.py
python3 -B toolchain/harness/executor/recovery/run_guarded.py 900 NEW_LIVE python3 -B toolchain/harness/executor/recovery/live.py NEW_LIVE/controls
python3 -B toolchain/harness/executor/recovery/run_guarded.py 1800 NEW_REGRESSION python3 -B toolchain/harness/executor/recovery/regressions.py NEW_REGRESSION/controls
```

Machine commands require exclusive lead release of `mo-executor-r01`. The 16
fixed groups are `create-before`, `create-response`, `reserve-response`,
`registration-before-reaper`, `active-owner-death`, `finalize-gap`, `complete-gap`,
`dispose-gap`, `repeated-cleanup`, `foreign-identity`, `malformed-linked`,
`lock-contention`, `unknown-transport`, `late-bootstrap`, `application-active`,
and `application-snapshot`. `--groups` rejects unknown, empty and duplicate
selections before output creation or machine activity. Fault injection is
confined to these tests and their exact resources; production has no fault flag.
The actual process-death group kills a known child after candidate registration;
other phase controls explicitly abandon their test object before cleanup.
The live `malformed-linked` group tests a receipt symlink; local tests additionally
cover hard links, nonprivate directories, invalid schemas/bounds, proof flags,
and malformed matching-ID transport responses. Foreign refusal checks the
unchanged target-state hash and absence of a terminal before restoring its
operator receipt. Final cleanup statuses, actual group absence, and the total
16 MiB attempt ceiling are asserted, not inferred from command exit.

The regression runner invokes unchanged workspace22, executor17, lifecycle1,
and application23 control bodies. Its only application test adaptation redirects
the generated source cache into this directory's evidence output. The local
runner includes inherited local27/policy8/package3 and added recovery tests,
without counting imported/inherited policy test methods a second time.
All failures stay in `evidence/`; see `WORKER-REPORT.md` for actual counts,
exits, attribution, final inventory, limits and unresolved gates.
