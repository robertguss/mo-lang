# Workspace recovery v1 worker report

Base: `90858791f441d125f0187a6751beffec6ef2312b`, clean at entry.
Worker pane `w4:p21`, owned right/no-focus run pane `w4:p22`, lead `w4:p1`.
Worktree `harness-workspace-recovery-v1`; branch `harness/workspace-recovery-v1`.
Implementation is confined to recovery/, workspace.py, workspace_controller.py,
adapter.py, remote.py, and executor README. No nested agents, pushes, rebases,
compiler/example edits or installed-file/image/unit/config changes. Existing
slices were explicitly started only after later lead authorization.

Status: worker implementation and verification complete; independent lead
acceptance pending. Lead owns mo-executor-r01 exclusively after the final release.
Machine and full compiler release were explicitly received before those runs.

## Numbered worker decisions

1. One cleanup-only function consumes a versioned private ownership receipt;
   no execution reopen/resume or HTTP API.
2. Hold a kernel file lock for the original Workspace object's whole lifetime,
   including split start/collect calls. Process death releases it naturally;
   recovery cannot steal a live owner.
3. Persist execution/call intent before reserve and dispatch intent before start.
   Keep old manifests/results as supporting records and never evaluate retained
   caller script/source during recovery.
4. Use a persistent terminal workspace record outside deleted roots. Create and
   bootstrap check it under the existing registration lock; bootstrap checks
   before root.mkdir. Preserve registration-before-workspace ordering.
5. Persist cleanup proof in terminal state before execution disposal and before
   deleting workspace state. Subsequent attempts confirm fresh absence and use
   retained proof for exact cgroup identity, including interrupted disposal.
6. Unknown original execution stays unknown even after cleanup is confirmed.
   No recovery execution result can carry a synthesized application pass.
7. Use 16 fixed recovery groups; related interruption phases share groups.
   Keep all failed attempts and separate local proof from dedicated-machine proof.

## Retained failures

- `evidence/red-01`: 2 expected missing-ownership errors, exit 1.
- `evidence/live-01`: evidence-wrapper path normalization error before launching
  test/machine activity; retained pane traceback, no candidate run.
- `evidence/live-02`: create transport bootstrap indentation regression caused
  by method wrapping; fixed, exact owned inventory clean, exit 1 retained.
- `evidence/live-04`: first disposal cleanup succeeded but repeated cleanup lost
  a completed execution's proof when workspace state was removed. Fixed by
  retaining that proof in the terminal before deletion. Its original terminal
  records are historical failed-attempt artifacts, not final implementation proof.
- `evidence/red-dispose-01`: expected failure reopening partially removed
  execution storage; fixed by using persisted terminal proof plus fresh absence.

Final command exits, attribution, source identities, limitations and release
inventory are retained below and in evidence/FINAL-RECEIPT.json.

## Frozen source checkpoints

- `08525c614b32b71b4f6101ecc93eb6e8f6d68797`: initial source/test/docs checkpoint.
- `00a0665790a1692c1b529b7b676cdcfa1a94990f`: approved interruption,
  healthy-delete, identity/proof and harness corrections. Both author and
  committer are `GPT-6-Astra <noreply@openai.com>` on both commits.

Additional decisions after review:

8. Persist exact `.owner-<workspace_id>` machine ownership before root.mkdir.
   Recover partial create only from matching ownership, never directory scanning.
9. Persist reserve call identity, and use exact reserved-not-started authority,
   terminal barrier and positive runtime absence to clean before bootstrap
   transport or manifest creation. Do not infer absence from a missing root alone.
10. Ordinary healthy delete retains completed execution proofs in its retired
    record. Reject omitted completed IDs before cleanup side effects.
11. Every accepted cleanup proof requires all three flags to be Boolean True.
    Host responses have an exact bounded schema, phase/identity whitelist and
    no contradictory confirmed/unresolved fields or application verdict fields.
12. Require confirmed/unknown final API cleanup results in addition to physical
    inventory. Measure total attempt bytes and assert owned process-group absence.

## Verification

| Attempt | Result |
| --- | --- |
| `local-final-02` | 59/59: inherited local27 + policy8 + package3, added21; exit 0; group absent; 273099 bytes |
| `recovery-final-04` | 16/16 fixed groups; exit 0; all final cleanup API results confirmed/unknown; group absent; 432232 bytes |
| `regressions-01` | workspace22, executor17, lifecycle1, application23 all exit 0 on initial source; superseded by corrected-source rerun below |
| `full-build-01` | `zig build` exit 0; 38.2 seconds; group absent; 266920 bytes |

The new 21 local tests include 30 combinations of missing/false/non-Boolean
proof flags across terminal/completed state, matching-ID malformed-response
negatives, missing source-state/bootstrap-manifest interruption, pretransport
dispatch intent, healthy delete/recover, and completed-ID omission. Test counts
exclude six duplicated imported/inherited policy method invocations that the
unfiltered unittest module loader otherwise repeats.

Additional retained failures:

- `red-edges-01`: three expected failures for partial bootstrap/create and omitted
  completed IDs. `red-edges-02`: five expected failures adding healthy delete and
  dispatch intent before bootstrap. The correcting source checkpoint preserves
  both attempts.
- `red-validation-01`: two negative test methods with 31 recorded assertion
  failures before the independent identity review fixes.
- `recovery-final-02`: syntax error in a test-only quoted injection before any
  machine/candidate activity; preserved and corrected in `recovery-final-03/04`.

Coverage precision: `malformed-linked` live group exercises a receipt symlink.
Hard links, nonprivate directories, malformed record bounds and identities are
local-only controls. Host owner contention is exercised with a live started
candidate across the public start/collect interval. Identity-refusal live checks
compare target state hash and terminal absence immediately before/after refusal.
No destructive machine-stop/poweroff fallback is exercised by recovery.

## Runtime interruption and authorized operator cleanup

The corrected-source parallel run `regressions-final-01` failed workspace22 at
19/22. It did not run executor17/lifecycle1/application23. The first snapshot
transport returned to the inherited adapter but failed JSON decoding at offset
zero; the inherited helper did not retain successful stdout/stderr. Exact first
bytes remain unknown, so no transient or root-cause claim is made. Later
registration refusals and inherited collector machine-stop fallbacks caused a
separate restart cascade. See immutable `evidence/RUNTIME-INTERRUPTION.md` and
`runtime-diagnostic-01/02` for the exact identities and ET journal chronology.

After explicit lead authorization, `operator-cleanup-02` handled the exact 15
receipts from that failed workspace run. The normal API confirmed 14 and left
one (`c6dac6e58cfd4a119cdcf20afb2e46c2`) unresolved because a started execution's
proof was lost across machine restart. That API result remains unresolved.
Separate explicit operator cleanup validated exact owner records and fresh
container/unit/parent-cgroup absence, then removed only the remaining named
workspace/execution directories. It preserved owner, retired and terminal
records and did not forge proof or claim whole-machine recovery.

`operator-cleanup-01` and `readiness-probes-01` conservatively failed their
read-only parent proof after restart: unloaded inactive slices had an empty
ControlGroup. The diagnostic scripts were corrected to require successful
`ActiveState=inactive`, empty ControlGroup, and absence of the exact previously
known `/mo.slice/<parent>` hierarchy. They did not start slices or change config.
The corrected cleanup succeeded; `readiness-probes-02` verified both pinned
image IDs, the package manifest hash, exact old/application parent limits,
positive runtime absence, and 20/20 read-only inherited snapshot probes with
actual rc and exact stdout/stderr retained. The machine was already running;
no extra explicit restart was issued.

The subsequent regressions ran sequentially with no compiler workload and a bounded
test-only gzip transport observer. Existing control bodies remain unchanged;
there is no swallowed failure, automatic retry, or product-source correction.
The observer stores argv, input, real exit, stdout/stderr and timestamps; stream
bounds/truncation and hashes are explicit. Fresh output directories retain every
attempt independently.

`full-test-01` failed 242/243 (3/5 build steps), exit 1, at unchanged
`toolchain/src/corpus.zig:1243`: the fatal-alert/reset TLS test produced
`Handshake/Closed` in a different order. This differs from the lead's earlier
TCP-count failure. Its owned group is absent. Compiler/corpus source is unchanged;
the authorized fresh sequential suite completed after machine work stopped
(see full-test-02 below), without any claim that a rerun fixes TLS ordering.

The second owned right/no-focus run pane was `w4:p26`; it was created only for
command execution, never another agent. Both owned run panes were closed
after idle status and process-group absence were verified.

## Observed restart provisioning failure

`workspace-observed-01` failed (exit 1) before its first candidate executed:
its actual observation was infrastructure_failure with `missing slice control
group`. The worker incorrectly accepted inactive/absent slices as execution
readiness; that only establishes cleanup absence. This is a demonstrated
provisioning cause, separate from the earlier unexplained malformed snapshot.
Exact gzip transport records and `OBSERVED01-DIAGNOSIS.json` retain the response.
Operator cleanup for this attempt passed, retaining 14 API confirmed and one
unresolved result rather than inventing reboot-lost proof.

Lead expressly authorized `systemctl start mo-executor.slice mo-application.slice`
only after exact cleanup. `readiness-probes-03` retains unchanged unit-content
hashes before/after activation, active exact ControlGroup paths, effective
memory/swap/CPU/PID limits, empty parents, pinned image/package identity and
20/20 raw read-only snapshot probes. No installed unit/config/image changes or
product auto-provisioning were made. Fresh observed regressions followed this gate.

## Reproduction and diagnostic boundaries

All commands below run from the worktree root in an owned right/no-focus pane,
using a fresh output directory. The wrapper snapshots source identities, applies
a numeric process-group guard, retains the real exit and proves group absence.

```sh
python3 -B toolchain/harness/executor/recovery/run_guarded.py 600 FRESH_ATTEMPT python3 -B toolchain/harness/executor/recovery/observe_regression.py workspace22 FRESH_ATTEMPT/results
```

Use `executor17`, `lifecycle1`, or `application23` for the other unchanged
regression bodies (application guard 900 seconds). The observer captures orbctl
subprocess.run calls in its own process, with exact bytes up to 1 MiB per stream
and a 4 MiB compressed cap, explicit truncation and SHA-256. Independently
spawned inherited child controllers retain their normal logs; this observer
does not instrument those child interpreters. There is no transport retry or
exception suppression.

`readiness_probes.py OUTPUT --activate-existing` is an explicitly authorized
test/operator action, never part of product recovery. It starts only existing
parent slices, records unit text/hash before and after, and then requires active
exact paths and effective limits. Without that flag it is read-only.
`operator_cleanup.py RECEIPT_DIRECTORY OUTPUT` is likewise a separate operator
tool: only explicitly authorized exact IDs, fresh identity/absence checks before
deletions, no invented API proof and no whole-machine recovery claim.

## Sequential observed regressions on frozen product source

All four fresh suites ran sequentially after active-slice readiness and without
concurrent compiler work. No product correction or automatic retry was made.

| Attempt | Controls | Exit | Group absent | Total retained bytes |
| --- | --- | --- | --- | --- |
| `workspace-observed-02` | 22/22 | 0 | True | 3579280 |
| `executor-observed-01` | 17/17 | 0 | True | 996037 |
| `lifecycle-observed-01` | 1/1 | 0 | True | 351070 |
| `application-observed-01` | 23/23 | 0 | True | 3470296 |

`final-inventory-01` exited 0: 178 recorded workspace roots, 234 execution
resources and 190 recorded candidate cgroups absent; 44 historical local groups
absent; exact active parent paths with empty task sets and no Docker child
cgroups; five shared Mac Docker IDs/states unchanged. All historical attempt
directories are measured below 16 MiB. Inventory counts include records from
retained failed attempts and local negative controls, not just successful runs.

Diagnostic source checkpoint `df816be3` contains only owned test/operator
scripts and final-inventory assertions. `c2ea7cf7` contains earlier inventory
assertions. Product files are unchanged from `00a06657`. Every checkpoint uses
explicit `GPT-6-Astra <noreply@openai.com>` author and committer.

## Contract and scope limits

The API is `recovery.recover(ownership_path, seconds=60)`, for newly journaled
workspaces only. Its versioned 1 MiB private receipt binds run/workspace IDs,
canonical directory, policy/image/toolchain and up to 1000 execution/call intents.
Supporting manifests/state remain authority; no retained script is evaluated.
The bounded response names cleanup confirmed/unresolved independently from
execution unknown, completed phases/IDs, unresolved IDs and sanitized errors.
The original live owner holds the lock across start/collect; process death
releases it. No execution resume/retry, HTTP, new policy, legacy adoption or
whole-machine crash-recovery claim is included. Local I/O/process launch and
machine failure prevent an unconditional finite wall-time guarantee.

Reboot-lost started proofs for `c6dac6e58cfd4a119cdcf20afb2e46c2` and
`d9fb2178a6da42bcaff924f958d030ef` remain API-unresolved. Explicit operator
cleanup separately establishes physical absence and preserves ownership/terminal
records. The first earlier malformed snapshot remains unexplained; the later
inactive-slice failure is explained and is not evidence of the same cause.
The retained first full compiler failure remains a failure; the green fresh run
establishes non-reproduction, not a fix for TLS ordering. Lead acceptance and
independent integration remain separate from this worker handoff.

## Final handoff

`full-test-02` passed 243/243 tests and 5/5 build steps, exit 0 in
406.516 seconds; process group 57911 absent; 279071 retained bytes.
This proves non-reproduction only of the retained first TLS-ordering failure.
`full-build-01` previously passed on the same product source.

`final-inventory-02` exited 0 after the compiler completed: all 178 recorded
workspace roots, 234 execution resources and 190 actual candidate cgroups
absent; both active parents empty; shared five Docker IDs/states unchanged.
It checked 46 historical groups; its wrapper separately proved its own group
absent. The final post-pane-close local scan checks all 47 recorded groups
absent. Every attempt remains at most 16 MiB (maximum 3579280 bytes).
Both owned run panes w4:p22 and w4:p26 are closed after shell-only idle checks.
Worker pane w4:p21 and all other panes are preserved.

`FINAL-RECEIPT.json`, `TRANSPORT-SUMMARY.json`, `PRODUCT-FREEZE.json`, the
final inventory, original attempt directories and `MANIFEST.json` retain the
reproducible evidence. All observed capture streams were untruncated.
The report/evidence commit is separate from source; no evidence still has an
active writer. No tracked compiler/example changes, push or rebase occurred.
The final handoff explicitly released dedicated mo-executor-r01 to lead w4:p1,
who acknowledged exclusive ownership; independent lead acceptance remains pending.
