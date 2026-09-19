---
title: "Mo workspace foundation: persistent files and protected snapshots"
created: 2026-09-19
updated: 2026-09-19
type: plan
tags: [agents, tooling, verification, security]
sources: [plans/mo-first-coding-harness.md, plans/mo-executor-foundation.md]
status: complete
---

# Mo workspace foundation: persistent files and protected snapshots

## Orientation

Next bounded executor slice under Robert's overnight authority. The accepted
[[mo-executor-foundation]] executes ephemeral BusyBox fixtures and binds checks
to scripts. This slice adds a disposable session workspace, real file/command
feedback and a protected snapshot identity. [[mo-coding-fixture-v1]] remains a
separate Mo orchestration slice. No provider, HTTP bridge or application-build
acceptance is included here.

Read-only design evidence is in
`audit/evidence/2026-09-19/workspace-readiness/`. The lead chooses a smaller
first slice than that review's HTTP/helper-image proposal: reuse the pinned
BusyBox image for shell feedback and run fixed Python file operations in the
trusted Linux controller with descriptor-based path handling. Candidate shell
text always runs inside the accepted container boundary. The controller never
executes candidate paths or deserializes candidate objects as code.

The dedicated machine is still `mo-executor-r01`; the shared Mac Docker daemon
is outside worker scope. A lead-owned Linux compiler build may be active when
this worker starts. Implement and run local unit checks first; live machine
tests start only after the lead reports that build stopped. This resource
dependency is not permission to change build services or machine limits.

## Write scope
One fresh Astra/low worker, separate exact-base worktree; no nested agents.
Own new workspace controller/helper/tests and documentation/evidence under
`toolchain/harness/executor/`, preferably `workspace.py`,
`workspace_files.py`, `test_workspace.py`, `test_workspace_live.py` and
`evidence/workspace-v1/`. Narrow edits to `adapter.py`, `remote.py` and README
may add the explicit workspace policy and feedback result path.

Preserve the existing fixture policy, public Run/check requirements and all
historical evidence. No compiler/runtime/Agent/provider/wiki/shared recipe
changes, new package dependencies or global Docker/systemd configuration.
Do not hand-edit old evidence. Local commits use actual GPT-6-Astra author and
committer; no worker push or rebase. Lead owns integration and acceptance.

Live tests may create only task-named workspace/snapshot directories and
size/inode-limited tmpfs mounts under `/var/lib/mo-harness/`, plus the existing
task-named executor containers/transient services. Never mount Mac paths.
Remove only owned mounts/directories after confirmed cleanup and retained
evidence. All tests/builds/servers use numeric guards in owned right/no-focus
Herdr panes, with process-group and machine-local cleanup.

## Parts

### 1. Workspace identity, bounds and sequential ownership

The trusted caller creates one random workspace ID bound to one run ID. The
Linux controller owns registry, locks, mount root and lifecycle state outside
candidate storage. The candidate owns only its data subtree as UID/GID 65534.
Use a dedicated 64 MiB tmpfs with 4096 inode limit, noexec/nosuid/nodev, beneath
a root-owned administrative directory. Read back effective mount bounds.
No persistence across reboot is promised.

Import only a caller-supplied bounded mapping of relative paths to file bytes;
no archive extraction, Git metadata, shared hardlinks or automatic recursive
Mac upload. Maximum 1000 files and 64 MiB total, each file at most 64 KiB.
Reject duplicate paths and malformed input before publishing a ready workspace.
An invalid import leaves no usable partial workspace.

Serialize each operation through a machine-side exclusive workspace lock.
Retain the executor's single-active-candidate constraint. File operations,
snapshotting and deletion require preceding command cleanup to be confirmed.
Unknown cleanup quarantines/closes dispatch and retains existing fail-closed
machine-stop behavior; never silently reuse an uncertain workspace.

Every caller operation has a unique call ID, finite deadline and matching
run/workspace identity. Record the start claim before dispatch. Reject duplicate
or foreign calls; uncertain outcomes are never replayed automatically. Start
claims and lifecycle records are trusted, not files in the candidate subtree.

### 2. File operations

Offer list_files, read_file, literal search, write_file and exact_edit through
the trusted Python API. No host shell interpolation for paths or file data.
Reject absolute paths, NUL, `..`, empty/noncanonical components and overlong
paths. Permit `.` only as the list/search root. Walk directory descriptors with
no-follow opens at every component. Use nonblocking opens then fstat; accept
only regular files/directories, reject symlinks, special files and file link
counts other than one. Do not use realpath followed by ordinary open.

No candidate process may run while the controller traverses its files.
Commands may create hostile entries, so validate on each operation and snapshot.
Text tools require valid UTF-8 and operate on encoded bytes; invalid input or
file content is an explicit refusal. List/search are deterministic, bounded to
1000 files/200 hits and a 64 KiB serialized result with explicit truncation.

Exact edit requires nonempty old text and exactly one literal occurrence,
counting overlaps. Original and result must fit 64 KiB. Missing/multiple/denied/
oversized edits leave the destination unchanged. Write a fresh same-directory
regular temporary file and rename under the lock; remove owned temporary files.
Preserve all other bytes. State replacement semantics and uncertain timeout
outcomes; do not claim crash durability.

### 3. Real feedback commands using existing cleanup

Add one explicit workspace policy beside the unchanged fixture policy. It uses
the same pinned BusyBox image and resource/security restrictions, with only the
registered candidate data subtree bound at `/workspace` read-write. Working
directory is `/workspace`; no arbitrary image, root, mounts, devices, network,
environment or policy supplied by candidate text. Validate effective Docker
configuration including the exact source/destination/mode of the single mount.

Command text (at most 32 KiB) becomes `/bin/sh -c` argv data inside the container.
Retain 0.25 CPU, 64 MiB memory, zero extra swap, 16 PIDs, combined 64 KiB output
and 0.5–10 second execution bounds. Feedback returns success/refusal/failure/
timeout/cancellation, nullable actual exit code/signal, separate stdout/stderr,
truncation, elapsed time and execution completed/not_started/unknown.

Exit zero is command success only. Separate execution validity from behavioral
acceptance; do not add dummy checks or weaken the existing nonempty-check Run
API. Keep structured failure and allowlisted diagnostics; a successful RPC or
printed verdict is not command/task success.

Reuse timer-before-supervisor registration, one-shot start, bounded capture/
drain and all accepted lifecycle ordering. Stop supervisor, prove container and
cgroup absence, persist proof, then disarm deadline units and prove their
absence. Do not introduce a second weaker lifecycle for mounted workspaces.

### 4. Closed candidate and protected verification handoff

Finalization closes further dispatch and confirms all writers are gone. Copy
validated regular-file bytes into a new protected snapshot, never hardlinks.
Bind a canonical sorted inventory of paths, lengths, content digests and
explicitly normalized executable/nonexecutable mode. Reject special entries,
oversized trees and unsupported permission bits. Document mode normalization;
snapshot identity must describe the bytes/modes actually used for verification.

The candidate cannot mutate snapshot storage, manifest, requirements, check
inventory, verifier or results. A final verification run mounts only the frozen
snapshot read-only, uses fresh bounded scratch, and uses externally supplied
nonempty checks. Bind verdict to run/workspace/snapshot, image/toolchain policy,
verifier and check-inventory identity, observations and positive cleanup proof.
Recheck snapshot identity before dispatch; stale/mutated snapshots fail.

For this slice, use independent synthetic shell/file behavioral controls with
the pinned BusyBox image. No arbitrary candidate-built executable, Mo build,
application verdict, HTTP service or transport integration claim.

## Numbers and done when
At most 30 named workspace controls per attempt; 600-second test guards and
16 MiB retained evidence per attempt. Keep every failed attempt. Existing
15-unit/17-live executor controls and collector-loss regression must still pass.

Demonstrate import → command failure → inspect → exact repair → command success
→ frozen snapshot → independent expected verdict. Record bytes and operation
order; a wrong candidate and forged printed success must fail final checks.
Exercise traversal, intermediate/final symlinks, hardlinks, FIFO/special-file
refusal, overlapping edits, invalid UTF-8, quota exhaustion, duplicate/foreign
calls, timeout/cancel, descendants surviving main shell exit, controller and
supervisor death with the workspace mounted, stale/mutated snapshot, empty
checks, missing fault stimulus and attempted result overwrite.

All commands have real exits, identities and cleanup snapshots. Final owned
container/service/mount/directory inventory is empty. Lead repeats integrated
tests plus an additional control and read-only shared Mac Docker comparison.
Report unimplemented requirements explicitly; green helper tests alone do not
close acceptance. No full compiler suite is required for Python-only changes.

## Result — independently accepted 19 Sep 2026, 2:02 AM ET

Worker 50f8a9d/d9444f0 integrated as bcdf7c1/f4fe3ea. Lead compared all 1586
changed files exactly and passed 27 unit tests, 22 workspace controls, 17 fixture
controls, collector-loss regression and two extra controls. The extras prove
active-command preservation on a refused second call and executable-mode/byte
identity through exact edit and frozen verification. All 2530 tracked executor
files stayed unchanged; shared Mac Docker retained the same five full IDs and
exited states. Final owned containers/units/cgroups/mounts/directories are absent.
Retired workspace-ID records remain intentionally, outside candidate storage.

Evidence: `audit/evidence/2026-09-19/workspace/attempt-01` and `extra-02`.
The first lead extra probe failed to observe descendants because its parent
shell exited; the corrected explicit-wait probe passed. Retain both. Worker
quota, duplicate-transport and stale-snapshot cleanup failures remain in its
immutable evidence. No historical failed result is relabeled green.

This scope is complete. Snapshot content omits empty directories and normalizes
file modes to 0755/0644. Real Mo application builds need a separately verified
image/resource policy; HTTP/Mo/provider integration remains the next slice.

## Related

- [[mo-first-coding-harness]]
- [[mo-executor-foundation]]
- [[mo-coding-fixture-v1]]
- [[decision-log]]
