# Existing caller contract for the next profile

Source reviewed in this worker's application-build-v1 patch; no API expansion.

- `Workspace(run_id, result_dir, *, policy=WORKSPACE_POLICY, image=IMAGE,
  toolchain=None)` creates the local object. Public attributes are `run_id`,
  generated `workspace_id`, `directory`, `selection`, `active`, `snapshot`.
- `create(mapping, **kwargs)` imports explicit bytes and returns the controller's
  `{mount, workspace_id}`. Policy/image/toolchain are supplied only at object
  construction and sent in the create request. `selection` is a plain dictionary,
  not an immutable accessor; mutating it cannot change the machine registry and
  mismatched subsequent reservation is refused.
- `start_command(script, *, checks=None, seconds=10, call_id=None)` returns a
  `WorkspaceRun`; `run.manifest` contains `image`, `policy`, `toolchain` (application
  only), command identity, `workspace_call_id` and `workspace`. The workspace
  binding contains `workspace_id`, `workspace_run_id`, `source`, `readonly`,
  `snapshot`, and application `policy/image/toolchain` values. The binding is
  persisted in the execution's `manifest.json`; there is no separate public
  get-binding accessor. `_prepare_command` is private.
- `command(script, *, seconds=10, call_id=None)` starts and collects synchronously.
  `collect()` calls `run.collect()`, controller `complete`, then `run.dispose()`
  before clearing `active` and returning feedback. `Workspace` has no public
  dispose method: `delete(**kwargs)` removes its source/snapshot. Direct
  `WorkspaceRun.dispose()` concerns the execution's machine evidence.
- `freeze(**kwargs)` returns `{snapshot, inventory}` and sets `snapshot`.
  `verify(script, checks, *, seconds=10, call_id=None)` requires nonempty external
  checks and runs the snapshot command through the same lifecycle.

## Timing: configured waits, not a proven end-to-end maximum

Sources: `workspace.py` (`call`, `_prepare_command`, `start_command`, `collect`),
`adapter.py` (`remote`, `_lifecycle`, `_start`, `_collect`, `dispose`), and
`remote.py` (`finalize`, `reap`, `supervise`).

For a requested 120-second candidate:

| Stage | Configured allowance |
| --- | --- |
| `Workspace.create()` controller RPC | default 30 seconds + 5 transport = 35 seconds |
| `start_command()` reserve RPC | default 30 + 5 = 35 seconds |
| Run bootstrap/start RPC | 6 seconds |
| Run collection observation loop | `seconds + 10` = 130 seconds, with a final RPC potentially adding 6 seconds and a 0.1-second sleep |
| Finalize RPC | 6 seconds |
| Unknown-cleanup machine-stop fallback | up to 10 seconds; transport timeout can raise instead of returning a result |
| Workspace completion RPC | default 30 + 5 = 35 seconds |
| Run disposal RPC | 6 seconds |

Thus roughly 234.1 seconds of configured waits for start plus collection,
completion and disposal, excluding initial create. The healthy cleanup path
omits the 10-second machine-stop fallback. A separate direct disposal would add
another 6-second RPC if it was not already disposed. General file/controller
calls accept 0.5..60 seconds, with `seconds + 5` transport timeout.

**There is no proven finite public wall maximum.** `_lifecycle` uses blocking
`flock(LOCK_EX)` with no deadline. Local filesystem work and process creation are
not bounded by a shared operation deadline. Machine transport timeouts do not
establish completed remote work or successful cleanup. Consequently neither
120 seconds nor the approximate sum above is an unconditional cleanup-safe HTTP
deadline. The next profile needs separate controller lifetime/cleanup ownership
and truthful unknown results; it must not discard cleanup merely because an HTTP
request expires. This worker has not widened or redesigned that contract.

Machine execution is independently guarded: registration sets the candidate
deadline; deadline timer is `seconds + 2` (122 seconds here), supervisor
`RuntimeMaxSec` is also `seconds + 2`, stop grace is 2 seconds, and the separate
reaper has `TimeoutStartSec=8s`. Reaper removal uses a 3-second budget; finalizer
keeps it armed until supervisor/container/cgroup absence is proved. These are
configured service limits, subject to service scheduling and host failure, not
a synchronous caller wall-time guarantee.

The old provider 2-second/30-second profile and existing controller
`files.CAP - 256` (65280-byte) refusal are unchanged.
