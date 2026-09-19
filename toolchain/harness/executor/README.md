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
The checks are copied at construction. The manifest records policy/verifier
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
- Cleanup queries the daemon successfully, checks the **actual systemd cgroup
  hierarchy**, and confirms no run units remain. The host does not publish a
  pass before these checks. Unknown host cleanup requests `orbctl stop
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

The unit suite has nine tests, including missing/empty checks, missing
observations, stale run/candidate identity, forged success, absent fault stimulus,
effective-policy mutations, cgroup hierarchy, defensive check copying, and
fail-closed machine-stop branches. Its effective-policy baseline is the retained
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
