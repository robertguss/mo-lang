**Recommendation:** use a loopback HTTP front end with one serialized subprocess owner whose lifetime is independent of requests. A bridge-only implementation can preserve cleanup ownership across client disconnects, but reliable recovery across interrupted preparation needs a narrow core recovery API. Killing a subprocess at the HTTP deadline is insufficient.

All references below are to immutable checkpoint `55cbb14ceba7f67d5f817f86b68f5596ae1357b8`, under `toolchain/harness/executor/`.

**Source-backed facts**

- **Start is one-shot; transport failure does not permit replay.** `Run.start()` persists `start-requested` before dispatch; collection/disposal closes future starts. Local lifecycle operations take a blocking flock. (`adapter.py:105–116,159–164,201–207`)
- **Cleanup has distinct stages.** `Workspace.collect()` performs execution collection/finalization → controller `complete` → execution disposal → clears `active`. An exception interrupts that sequence. `delete()` separately removes workspace storage/snapshot. (`workspace.py:180–188,228–229`)
- **Preparation has a recovery gap.** The execution manifest exists before `reserve`, but its full workspace binding, call ID, and local `active` assignment occur only after the reservation response. A lost response can leave a machine-side active reservation without a fully bound local execution manifest. (`workspace.py:156–173`; `workspace_controller.py:153–162`)
- **Independent candidate cleanup begins during registration.** Bootstrap authorizes the reservation, writes the deadline, installs the reaper timer, then dispatches the supervisor. Failure before timer installation is outside that independent guard. (`adapter.py:126–149`)
- **Finalization protects against late registration.** Bootstrap and finalizer share the registration lock. Finalization stops the supervisor, proves container/cgroup absence, persists proof, then disarms the reaper and confirms unit absence. Reaping alone does not complete the workspace reservation or delete its mounts. (`remote.py:143–189,208–227`; `workspace_controller.py:128–151`)
- **Unknown stays unknown.** Transport exceptions record `execution='unknown'`; execution feedback requires identity, execution, and cleanup evidence. A client timeout is not evidence of candidate timeout or cancellation. (`workspace.py:15–52,114–123`)
- **Quarantine does not imply cleanup.** Unknown controller operations quarantine the workspace. `complete` requires matching active execution and positive cleanup proof; successful completion clears `active` but does not reset quarantine. Deletion is permitted through quarantine once no active reservation remains. (`workspace_controller.py:85–89,128–152,298–303`)

**Existing recovery primitives and records**

There is **no public reopen/recover API** in `Workspace` or `WorkspaceRun`. Existing primitives are `cancel()`, `collect()`, `dispose()`, `Workspace.call/require('complete', …)`, and `delete()`. Machine-side `finalize(root)` and `dispose(root)` are callable Python functions, not recovery CLI modes. (`workspace.py:55–229`; `remote.py:364–369`)

The checkpoint’s recovery example manually reconstructs objects with `__new__`, reads registry state, restores machine manifest/source, then collects and deletes. This is evidence of a manual procedure, not a supported recovery interface. (`test_workspace_live.py:258–265`; `evidence/workspace-v1/recover_live01.py:12–27`)

| Location | Persisted evidence |
|---|---|
| `<workspace result_dir>/call-<call_id>/request.json`, `result.json` | Workspace/run/call identities, requested operation, reservation execution ID where applicable |
| `<workspace result_dir>/execution-<random>/manifest.json` | Execution identity; full binding only after reservation succeeds locally |
| Same execution directory | `start-requested`, `closed`, `disposed`, `lifecycle.lock`, `result.json`, output files |
| `/tmp/mo-executor-<execution_id>/` | `manifest.json`, `registration.json`, `observation.json`, `reaped.json`, `cleanup-confirmed.json` |
| `/var/lib/mo-harness/mo-workspace-<workspace_id>/` | `state.json`, `calls/<call_id>`, `calls/<call_id>.result`, storage/snapshot, snapshot inventory |
| `/var/lib/mo-harness/.retired-<workspace_id>` | Successful deletion tombstone |

Sources: `adapter.py:90–103,133–145,193–207`; `workspace.py:93–124,164–171`; `remote.py:159–188,222–225,280,361`; `workspace_controller.py:18–33,77–82,184,244–251,304–317`.

**Smallest proposed architecture**

1. **One owner, one admitted operation.** Bind the HTTP listener explicitly to loopback. A separate owner process serializes the application run’s workspace operations. Reject concurrent submissions rather than queueing work that might begin after its caller times out.
2. **Persist ownership before remote effects.** Keep one private bridge journal containing the known run/workspace IDs, evidence directory, operation identity, and cleanup phase. Persist workspace ownership before `create()`. Existing call receipts and execution manifests remain authoritative supporting evidence.
3. **Separate client waiting from execution ownership.** Give each HTTP request a finite configured deadline. On expiry, return an unknown outcome if possible; on disconnect, stop response delivery. In both cases the owner continues collection and cleanup. Do not automatically replay the operation or resume the application sequence.
4. **Retain ownership until cleanup is resolved.** After timeout/disconnect, stop accepting further application work. Follow finalize → complete → dispose, then delete owned workspaces when ending the run. Preserve evidence and an unresolved state when any stage cannot be confirmed.
5. **Recover only journaled ownership.** After owner failure, reconcile those exact workspace/execution identities and perform cleanup only. Do not launch candidates, recreate workspaces, reset quarantine, or scan and adopt unrelated resources.

**Bridge-only feasibility versus narrow core change**

Bridge-only ownership is feasible **while the owner survives**: the HTTP deadline need not interrupt core calls. A guarded subprocess also isolates a stuck lifecycle call from HTTP handling. However, terminating that child neither proves remote work stopped nor repairs partial reservations; local transport descendants and remote registration may still be in flight.

For reliable recovery, add a **cleanup-only core entry point** that:

- Opens retained identities without constructor side effects.
- Reconciles the known workspace registry, reservation receipts, execution manifest, and cleanup proof.
- Handles reserve-before-binding and registration-before-reaper interruptions under existing workspace/registration locks.
- Continues from an already successful `complete` without requiring that active reservation again.
- Finalizes, completes, disposes, and deletes only positively identified owned resources; otherwise retains unknown/quarantine.

This keeps machine-state reconciliation in the core instead of duplicating its private invariants in the HTTP bridge. No broad deadline rewrite is necessary for that ownership model.

**Timing limit:** finite client waiting is a configured policy, not an unconditional wall-time or cleanup guarantee. Blocking flock, local launch/filesystem I/O, service scheduling, and host failure remain outside a shared enforceable deadline. The contract explicitly rejects treating either 120 seconds or the approximately 234.1-second configured-wait sum as such a guarantee. (`application/HTTP-CONTRACT.md:35–69`)

Read-only inspection only; no edits, tests, or machine/network operations performed.
