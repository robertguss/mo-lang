# External fixture executor

A small Python stdlib adapter for the **dedicated `mo-executor-r01` OrbStack
machine**. It executes synthetic shell fixtures in the pinned, already imported
BusyBox image. It is not a Mo agent loop, provider client, plugin framework,
compiler acceptance, benchmark, or audit seal.

## Boundary and prerequisites

The caller, these Python files, Docker/systemd in the dedicated machine, and the
private host result directory are trusted. Candidate script/output are untrusted.
The caller defines every check; output is never parsed as a verdict, command, or
check inventory. No candidate command executes on macOS.

The lead provisions the isolated machine, disabled Mac filesystem/SSH-agent
integration, Docker, and `mo-executor.slice`. The adapter does not install or
reconfigure them. All Docker commands travel through the explicit argv prefix
`orbctl run -m mo-executor-r01 -u root` (no `--`). It never selects or invokes a
Mac Docker context. The shared kernel, compromised trusted host/runtime, and
whole-machine failures are outside this boundary.

The immutable local image is
`sha256:debdba9954b1065ab1ce723c6c1f2f22e52a78c164f863b938d58cc2c9f0d337`.
There are no pulls, host mounts, Docker socket mounts, or arbitrary file uploads.
Only the caller's UTF-8 fixture (at most 32 KiB) is passed as container argv data.

## Use

Import `Run` from this directory. The caller supplies a **new** result directory
and a nonempty check list. The directory is created with mode 0700. Check IDs are
unique; modes are `exact` or `contains`, streams are `stdout` or `stderr`, and
expectations must be nonempty. Fault-oriented checks must include both the
stimulus and its required effect. A marker alone does not prove resource
isolation; the live controls also inspect effective settings and kernel counters.

```python
from adapter import Run

run = Run("printf 'ok\\n'", [
    {"id": "answer", "stream": "stdout", "mode": "exact", "expected": "ok\n"},
], "/private/tmp/mo-executor-result-unique")
try:
    run.start()
finally:
    try:
        result = run.collect()
    finally:
        run.dispose()
assert result["passed"]
```

If `start()` raises after dispatch, still call `collect()` to retain an
infrastructure-failure result and confirm cleanup, then `dispose()`. `dispose()` rejects active runs so it cannot delete an active reaper's files.
Use `cancel()` followed by `collect()` for cancellation. `dispose()` removes only
that run's machine-side directory; host evidence remains.

A run registers its random ID, container name, fixture digest and deadline before
execution. An exclusive registration lock rejects another active candidate.
Lifecycle calls use a per-run host file lock. Start is one-shot, including lost
replies; collect or dispose closes future starts. Cancellation remains available
while collection waits. After confirmed disposal, disposal is idempotent and
collection rejects locally; the retained host result remains readable. Bootstrap, finalization and disposal share the machine's
registration lock, so an in-flight bootstrap cannot dispatch a supervisor after
cleanup proof. The checks are copied at construction. The manifest records policy/verifier
versions and SHA-256 identities of both adapter and supervisor source. Docker's
immutable image ID, effective command, and actual container ID are checked.
A previous result cannot pass under a new run or candidate identity.

## Containment and lifecycle

- UID/GID 65534, read-only root, all capabilities dropped, no-new-privileges,
  no network, private PID/IPC/cgroup namespaces, no mounts or devices supplied.
- 0.25 CPU, 64 MiB RAM, 64 MiB memory+swap (zero additional swap), 16 PIDs;
  `/work` and `/tmp` each 8 MiB tmpfs with noexec/nosuid. The parent slice adds
  the lead's aggregate CPU/memory/task limits. Docker logging is disabled.
- The execution deadline defaults to 10 seconds, measured from registration,
  including container setup. Tests may request 0.5–10 seconds. Cancellation,
  deadline and output overflow are distinct outcomes. A breached limit kills
  the container; attach pipes are drained for at most a two-second grace.
- stdout/stderr are separate byte streams with a **combined 64 KiB retained cap**.
  Extra output is discarded and cannot pass. A pipe client blocked after the
  bounded drain is killed and reaped. Actual Docker exit and attach-client exit
  are retained. `signal` is null because Docker cannot distinguish explicit
  `exit 137` from SIGKILL; `signal_hint` records the conventional interpretation.
- A systemd supervisor owns each run. Its `ExecStopPost` forcibly removes the
  container. A **separate systemd timer**, registered before the supervisor,
  triggers at deadline + two seconds, kills any surviving supervisor, removes
  the container, checks absence, records its independent result, and unloads its
  timer. It therefore survives both Mac-controller and supervisor-process death.
- Cleanup first stops **only the supervisor** and confirms it can no longer
  create writers. With the independent reaper still armed, it removes the
  container, queries the daemon successfully, and checks the **actual systemd
  cgroup hierarchy**. It persists this proof before stopping the deadline
  timer/service, then confirms all run units are absent. The result records this
  exact order. Disposal requires that proof as well as current unit/container/
  cgroup absence. The host does not publish a pass before these checks. Unknown host cleanup requests `orbctl stop
  mo-executor-r01`; unknown independent-reaper cleanup requests machine-local
  `systemctl poweroff`. No unqualified OrbStack stop exists in the adapter.
  The poweroff branches are unit-tested with simulated failures, not exercised
  destructively against the provisioned machine.

Missing observations, identities, policy evidence, checks, or cleanup evidence
fail closed. A killed supervisor normally has no terminal observation and thus
returns `infrastructure_failure`, even when its independent cleanup succeeds.
Host `result.json` includes expected/observed check outcomes, the manifest, raw
machine observation, cleanup confirmation and verifier identity. `stdout.bin`
and `stderr.bin` retain candidate output; neither can overwrite authoritative
results. Machine-local temporary evidence remains until `dispose()` so a new
trusted controller can inspect a dead controller's run.

## Verification

Run all commands from the repository root, in an owned Herdr run pane. Use fresh
attempt directories; never overwrite failed evidence. No Zig build is required.

```sh
python3 toolchain/bench/step36/guard.py 60 -- python3 -B toolchain/harness/executor/test_executor.py
python3 toolchain/bench/step36/guard.py 600 -- python3 -B toolchain/harness/executor/selftest.py /private/tmp/mo-executor-live-unique
```

The unit suite has fifteen tests, including missing/empty checks, missing
observations, stale run/candidate identity, forged success, absent fault stimulus,
effective-policy mutations, cgroup hierarchy, defensive check copying, and
fail-closed machine-stop branches, reaper-disarm ordering, uncertain removal,
surviving cgroups, one-shot dispatch, and start/collect/dispose serialization. Its effective-policy baseline is the retained
real record at `evidence/smoke-02/positive/result.json`.

The live self-test has 17 fixed cases, one candidate at a time:

| Controls | Required observation |
| --- | --- |
| Completion with descendants | Correct stdout/stderr; child/grandchild/new-session PID relationships; real cgroup exists then disappears |
| Wrong output, exit 7, forged verdict, host-result overwrite | External verdict rejects each candidate; real exit codes retained |
| Positive fault stimulus and omitted stimulus | Positive control passes; omitted stimulus fails |
| Timeout, cancellation, output overflow | Distinct status, checks actually emitted, bounded output, complete cleanup |
| CPU, RAM, PIDs | `nr_throttled`, `oom_kill`, and PID-limit event counters increase after named probes |
| Scratch | Small writes succeed; each 9 MiB write stops at exactly 8 MiB |
| Network/filesystem | In-container HTTP loopback works; external route denied; root write denied; host/socket aliases absent; non-root/caps/NNP observed |
| Controller SIGKILL, supervisor SIGKILL | Stimulus observed first; independent post-deadline container/unit/cgroup absence before host collection |

The self-test preserves every result, raw stream, running/cleanup snapshot,
source snapshot, actual controller kill status and summary. It checks the
machine's before/after container inventory, empty run units, and a 16 MiB artifact
budget. It cannot attest the Mac's shared Docker inventory because this worker's
scope explicitly forbids that endpoint; independent lead acceptance owns that
comparison and integrated-tree rerun. No claims are made for provider OAuth,
application builds, Mo/Agent integration, the 401 recipe, Pi comparison, Step 39,
Darwin full-sync, or suspended Program 7.

## Lifecycle fault regression

```sh
python3 toolchain/bench/step36/guard.py 600 -- python3 -B toolchain/harness/executor/test_lifecycle_live.py /private/tmp/mo-executor-lifecycle-unique
```

This single fixed control injects a failing `ExecStopPost` into only its own
transient supervisor, and an uncertain removal response into only its finalizer
process. It observes the real surviving candidate/cgroup and active deadline
timer, then SIGKILLs the collector before its host shutdown fallback can run.
The untouched machine-local deadline reaper must remove the container/cgroup
and unload its units before recovery collection. Fault code stays in the test;
there are no production fault switches or daemon/global configuration changes.
See `evidence/LIFECYCLE-CORRECTION.md` for the retained red test, corrected
ordering, raw live proof, and exact guarded commands.

## Session workspace (bounded synthetic shell/file slice)

`Workspace` in `workspace.py` is a trusted Python caller API. It has no HTTP or
provider bridge. Use a fresh 32-hex run ID and private result directory, then
`create({relative_path: bytes})`, `list_files`, `read_file`, `search`,
`write_file`, `exact_edit`, and `command`. Call `freeze()` to close candidate
writes and copy a protected snapshot; `verify(script, nonempty_checks)` runs
independent synthetic BusyBox checks against that snapshot read-only. Finally
`delete()` removes the owned mounts/directories. External checks and verifier
scripts must come from the trusted caller, never candidate output or files.

```python
from workspace import Workspace
import uuid

ws = Workspace(uuid.uuid4().hex, "/private/tmp/mo-workspace-unique")
ws.create({"answer.txt": b"wrong\n"})
assert ws.command('test "$(cat answer.txt)" = right')["exit_code"] == 1
assert ws.read_file("answer.txt") == "wrong\n"
ws.exact_edit("answer.txt", "wrong", "right")
assert ws.command('test "$(cat answer.txt)" = right')["state"] == "success"
ws.freeze()
result = ws.verify("cat answer.txt", [
    {"id": "answer", "stream": "stdout", "mode": "exact", "expected": "right\n"},
])
assert result["passed"]
ws.delete()
```

The registered source is the sole `/workspace` bind mount. The separate
`mo-executor-workspace-v1` policy retains the fixture image, UID, resource,
network, root-filesystem, output and lifecycle restrictions. Feedback command
success means exit zero with valid execution/cleanup evidence; it is not a
behavioral verdict. Feedback has no `passed` field and no fabricated checks.
`start_command`, `cancel`, and `collect` expose bounded asynchronous control.
Call collection even if dispatch raises after registration. Never automatically
retry an uncertain call; inspect retained request/result and cleanup evidence.

Each workspace uses a 64 MiB, 4096-inode noexec/nosuid/nodev tmpfs beneath a
root-only administrative directory in `/var/lib/mo-harness/`. Effective mount
options are checked at creation and dispatch. Only its data subtree belongs to
UID/GID 65534. Registry, call claims, locks, snapshots and results remain outside
candidate storage. Every operation has matching run/workspace/call identities
and a finite deadline. Machine-side locks serialize claims and operations;
active execution blocks file operations, freezing and deletion until the
existing executor persists positive cleanup proof. A trusted retired-ID file
prevents recreating a deleted workspace identity; workspace data has no
reboot-persistence guarantee.

Imports are explicit mappings (or ordered pairs, allowing duplicate detection),
not archives or recursive host uploads: at most 1000 regular files, 64 KiB per
file and 64 MiB total. Paths are canonical relative UTF-8, at most 4096 bytes and
255 bytes/component. Only list/search accept `.`. Directory descriptor walks
use no-follow opens for every component; nonblocking file opens are followed
by type/link-count validation. Symlinks, hardlinks, special files and setuid,
setgid or sticky bits are refused. Hostile candidate files are revalidated on
each traversal. Text reads/search/edits require UTF-8. List/search return sorted
bounded data with explicit truncation (1000 files, 200 hits, 64 KiB JSON cap).
Read responses that cannot fit the serialized cap are explicitly refused.

Exact edit counts overlapping literal byte matches and requires exactly one.
It preserves surrounding bytes and uses a fresh same-directory temporary file
plus rename, cleaning its temporary file on normal refusal/failure. Replacement
is atomic to observers under the lock, not crash-durable. A timeout after rename
can leave the new bytes in place: the outcome is unknown, never replayable.

Snapshot inventory hashes sorted paths, byte lengths, content SHA-256 and the
actual normalized mode: any executable bit becomes 0755, otherwise 0644.
Empty directories are omitted. Snapshot bytes are copied, never hardlinked.
Identity is rechecked immediately before dispatch. The frozen source mounts
read-only with fresh bounded `/work` and `/tmp`; candidate commands cannot
modify snapshot inventory, trusted checks/verifier or authoritative results.
Verdicts bind workspace/run/snapshot, pinned image/policy, verifier source,
check inventory, actual observations and positive cleanup evidence. This is
synthetic shell/file acceptance only; it makes no Mo/compiler/application claim.

Workspace evidence and bounded runners live under `evidence/workspace-v1/`.
Keep each attempt, including failures. Live work requires exclusive release of
`mo-executor-r01` by the lead; never use the shared Mac Docker endpoint.

## Explicit application policy

`Workspace(..., policy='application-build-v1', image='sha256:<content-id>',
toolchain='<package-manifest-sha256>')` binds a separate application policy at
creation. It uses the independently provisioned `mo-application.slice`, a
120-second command maximum and fresh executable `/build`; defaults above remain
the BusyBox workspace policy. The registered identity cannot change per command.
See [application/README.md](application/README.md) for pinned offline packaging,
resource limits and controls, and [application/HTTP-CONTRACT.md](application/HTTP-CONTRACT.md)
for the current public API and the limits of its caller wall-time guarantees.
