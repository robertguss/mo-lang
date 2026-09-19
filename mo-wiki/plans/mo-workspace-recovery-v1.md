---
title: "Mo workspace recovery v1: cleanup after owner loss"
created: 2026-09-19
updated: 2026-09-19
type: plan
tags: [agents, tooling, verification, security]
sources: [plans/mo-workspace-foundation.md, plans/mo-application-build-v1.md]
status: in-progress
---

# Mo workspace recovery v1: cleanup after owner loss

## Orientation

Add an explicit cleanup-only recovery path before building the HTTP workspace
adapter. A request deadline must not surrender ownership of a running command.
The existing API has no supported way to reopen a workspace for cleanup after
its owner dies. In particular, a reservation may succeed remotely while its
response is lost before the local manifest gets its full workspace binding.

The source-backed review is retained at
`audit/evidence/2026-09-19/workspace-wire-readiness/cleanup-review.md`, against
immutable application checkpoint `55cbb14c`. Lead decision: keep one serialized
owner independent of future HTTP request lifetimes, and first provide this
narrow core recovery seam. This slice has no HTTP server, Mo adapter, provider,
repair trial, new execution policy or compiler change. Overnight authority
permits the lead to choose this prerequisite without waking Robert.

## Write scope

A fresh Astra worker on low reasoning owns new
`toolchain/harness/executor/recovery/`, plus necessary narrow edits to
`workspace.py`, `workspace_controller.py`, `adapter.py`, `remote.py`, their
existing unit tests and executor README. Keep all existing evidence immutable.
New evidence, tests, report and README live under recovery/. No examples,
generated IDs, compiler, application packaging/control bodies, provider, wiki,
shared Mac Docker or other source edits. Do not fork another executor.

You are not alone. Preserve others' edits and use a separate worktree at the
lead's exact base. No nested agents, push, rebase, downloads, dependency or
machine configuration changes. Use explicit GPT-6-Astra author AND committer
for every local commit. Every test/build/server runs in an owned right/no-focus
Herdr run pane with a numeric guard and process-group cleanup. Retain failures.

Local implementation and tests are released immediately. Machine commands are
blocked until the lead explicitly releases `mo-executor-r01`; lead application
acceptance currently owns it. No /opt/image/slice changes are needed here.

## Contract

1. Persist a small private ownership receipt before the first remote effect.
   It names this workspace/run, policy/image/toolchain and its result directory.
   Persist execution/reservation intent before dispatching reserve, including
   execution ID and call ID. No crash-durability or fsync claim. Existing
   manifests, requests and observations remain supporting authoritative records.
2. Expose one documented cleanup-only API taking that retained ownership, with
   no constructor side effects and no requirement for the original Python
   object. Validate version, exact identities, selection and record bounds.
   Refuse malformed, symlinked, foreign or conflicting ownership. Do not execute
   caller-supplied script/source during recovery or adopt resources by scanning.
3. Reconcile only the named workspace and its recorded execution identities.
   Recovery may stop/finalize execution, complete its reservation, dispose its
   execution storage and delete its source/snapshot mounts. It must never start
   or retry a candidate, recreate a workspace, unquarantine it for new work,
   rerun a file operation, or synthesize a successful application verdict.
4. Cover owner loss before/after create response, reserve response, registration,
   reaper installation, finalization, complete and dispose. A reserve with no
   bound local manifest and a completed reservation with leftover execution
   storage must both be recoverable. Already deleted/retired ownership is
   safely recognizable; repeated cleanup may confirm absence, never replay work.
5. Establish an explicit barrier against late create/registration/dispatch.
   Cleanup cannot report confirmed and then permit a delayed owned bootstrap to
   create a candidate or leave fresh owned storage. Use existing lock ordering
   and narrowly scoped terminal records as needed; no global reset. Reconcile
   registration before workspace locks consistently with existing authorize.
   Retain a deterministic race control for delayed arrival after recovery.
6. Preserve cleanup-proof-before-reaper-disarm. Verify container, supervisor,
   unit and actual candidate cgroup absence before clearing ownership. Delete
   only exact owned mounts, with no recursive/lazy unmount. On missing or
   conflicting identity/proof, retain unknown/quarantine and evidence. Do not
   turn an inspect/transport failure into proof of absence.
7. Return separate cleanup status and original execution status. A lost outcome
   stays unknown even when cleanup is later confirmed. Include exact identities,
   completed phases and unresolved ownership, with bounded sanitized errors.
   No automatic recovery loop, automatic execution resume or HTTP endpoint.

This API operates on trusted operator records, outside candidate storage. It
does not grant a candidate the ability to recover or delete other workspaces.
Do not claim migration/recovery for old unjournaled workspaces; preserve their
existing behavior and document the explicit new-receipt requirement.

## Timing and compatibility

The application policy remains 120 seconds per candidate, 1 GiB, one CPU,
128 PIDs, existing tmpfs/output ceilings and immutable image/toolchain binding.
BusyBox defaults and old parent stay unchanged. No broad deadline rewrite.
Each recovery invocation has an explicit configured attempt budget and guarded
transport; inability to acquire a lock or establish proof returns unresolved.
Do not kill an unknown lock holder or steal a live owner. Local I/O/process
launch and machine failure preclude an unconditional finite wall-time promise.

Future HTTP code will retain a serialized owner beyond a client deadline and
use this API after owner loss. This slice proves only explicit cleanup recovery,
not unattended restart, whole-machine crash recovery or client receipt.

## Parts and numbers

1. Reproduce the interrupted-reservation/reopen gap with retained failing
   controls. Inspect actual lock and registration order before implementing.
2. Add minimal persisted ownership and cleanup-only reconciliation. Keep normal
   command/feedback behavior unchanged; test invalid ownership before effects.
3. Fix at most 18 named recovery groups before final evidence. Required coverage:
   create-response loss, reserve-response loss, registration before reaper,
   active descendant cleanup after owner death, finalize/complete/dispose gaps,
   repeated cleanup, foreign identity, malformed/linked receipt, lock contention,
   unknown transport, late bootstrap after confirmed cleanup, and preserved
   unknown execution status. Related phases may share a named group.
4. After release, run real dedicated-machine fault controls with recorded IDs,
   positive final inventory and no impact on other ownership. Use both BusyBox
   and application selection where policy affects cleanup; no new image build.
5. Re-run existing local27, policy8, package3, workspace22, executor17, lifecycle1
   and application23 controls. New local tests may increase counts; identify
   inherited and added tests separately. Retain full `zig build` and
   `zig build test --summary all` outputs. No unrelated fixes.

Live attempts use guards no longer than 1800 seconds; each attempt at most
16 MiB of retained evidence. Unknown/empty/duplicate explicit test selections
fail before machine or candidate activity. Preserve raw commands, exits, source
hashes, all failed attempts and cleanup evidence. Fault injection must be
explicitly scoped to owned test processes/resources and absent in normal use.

## Done when

Worker reports exact base and frozen local commit(s), actual attribution, clean
tree, API/record schema, numbered decisions, known limits, fixed control counts,
real exits and reproducible fresh-output commands. Prove all owned remote
services/containers/cgroups/mounts and local groups absent, compare the five
shared Mac Docker IDs/states read-only, then explicitly release the machine and
close only idle owned run panes. Preserve worktree and historical evidence.

Lead independently reviews and integrates, repeats applicable checks plus an
extra control, then records acceptance. An HTTP bridge brief follows only after
this recovery contract is demonstrated. No automatic acceptance from a receipt.

## Related

- [[mo-workspace-foundation]]
- [[mo-application-build-v1]]
- [[mo-first-coding-harness]]
