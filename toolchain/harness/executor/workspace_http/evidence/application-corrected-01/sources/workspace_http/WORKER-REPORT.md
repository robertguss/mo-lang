# Workspace HTTP v1 worker report — local correction frozen

Worker: GPT-6-Astra, low reasoning. Lead: w4:p1. Owned run pane: w4:p29,
created right/no-focus from worker w4:p28. No nested agents, push or rebase.

Exact base: `3023a01a744d1580ca9814e595ddf990a12e456d`.
Branch: `harness/workspace-http-v1`.
Worktree: `/Users/robertguss/Projects/startups/mo-lang-worktrees/harness-workspace-http-v1`.
Prior machine/compiler production source freeze: `83a72dd4ed55dd8728745af720a818399de4c81c`.
All changes are new files under `toolchain/harness/executor/workspace_http/`.
Core/provider/Mo/compiler/wiki/installed inputs remain unchanged. Every worker
commit explicitly sets GPT-6-Astra as author and committer.

## Contract and decisions

1. One operator-configured run/listener, loopback ephemeral port, private256-bit
   capability, six candidate tools. Lifecycle and cleanup recovery are private
   Python APIs. No candidate-selected policy, source paths, verifier or lifecycle.
2. One subprocess owns Workspace throughout construction, dispatch and cleanup.
   Known receipt/core/external identities and create intent precede create effects;
   each call hash/mapping/intent precedes dispatch. Actual results precede bounded
   frontend notification. No ACK, replay, work retry, replacement owner or fallback.
3. Admission is terminal after observed disconnect, unknown response or lease expiry.
   Original execution and HTTP delivery uncertainty are separate records. A late
   completed result cannot reopen admission or turn a lost response into receipt.
4. Fixed16 calls,900s admission lease,2s file/300s command response waits, candidate
   timeout500..120000ms,4MiB journal reservation. Core policy remains authoritative:
   BusyBox's existing10s command maximum is unchanged; application accepts120s.
5. Cleanup allowance60s: normal delete request at most55s plus Workspace.call's5s
   transport margin. Prior cleanup collection consumes the same remaining allowance.
   Blocking inherited collection/locks/local I/O can exceed a configured wall wait;
   unresolved stays unresolved. Explicit recovery requires proved owner death.
6. Response projection preserves completed refusals and actual exit/signal/status,
   including timeout/completed. Invalid base64/UTF-8 returns output_encoding with
   null text and preserved execution metadata. Raw results remain operator-only.
7. Independent review corrections: bounded post-write drain disposes only that
   connection; it cannot terminate a later request. One absolute write/close2s
   allowance. Partial IPC timeout and deadline-triggered EOF return504/unknown;
   premature owner failure returns200/owner_unknown. Both defects have retained
   REDs against immutable75680f31 and passing corrected controls.

## Verified evidence to date

Every named attempt is under `evidence/`, with command.json, head.txt, source
snapshots/hashes, output.log, real exit.json and process inventory. Real owner
transport is bounded raw gzip, preserving stdout/stderr/input hashes and bytes.

| Attempt | Result | Exit | Elapsed seconds |
|---|---|---:|---:|
| local-final-01 |22/22 fixed local groups, subprocess doubles |0|21.145|
| inherited-local-01 |59/59 inherited local tests |0|1.525|
| application-final-01 |22/22 real application-selection groups |0|45.817|
| busybox-final-01 |22/22 real BusyBox-selection groups |0|45.834|
| review-live-02 |2 additional controls within existing groups |0|8.619|
| regression-workspace22-01 |22/22 unchanged live controls |0|37.454|
| regression-executor17-01 |17/17 unchanged live controls |0|33.052|
| regression-lifecycle1-01 |expected infrastructure-failure cleanup control |0|9.681|
| regression-application23-01 |23/23 unchanged live controls |0|153.393|
| final-machine-inventory-01 |all retained IDs/resources absent, shared5 unchanged |0|0.464|
| readiness-final-01 |20/20 raw probes; exact final identity/effective limits |0|1.290|

All listed guarded groups were positively absent at wrapper exit. Final inventory
checked205 workspace IDs (including external HTTP IDs),126 execution IDs and123
actual observed cgroup paths; all were absent. It also checked23 earlier recorded
local groups; its own group88543 and final readiness group88631 were absent at
wrapper exit. Final effective limits/pinned images/manifest matched, runtime was
empty, and five shared Mac Docker IDs/states were unchanged. The machine was
explicitly released back to the lead before any compiler command.

Real matrices include all six HTTP tools; strict text/binary results; actual
controller result_too_large/completed refusals; containment refusal; no duplicate
execution; concurrent admission; actual registered candidate during frontend
SIGKILL/owner SIGKILL/disconnect; startup lost-create response; owner stall;
protected snapshot verifier; exact imported source comparison; pinned application
selection and configured120000ms command; lost cleanup response followed by a
separate successful cleanup-only recovery. Source canaries check host paths and
operator config are absent from the candidate. No shared Mac candidate executes.

Actual controller numeric validation is retained under each final matrix's
`controls/deadlines/controller-deadline.raw.json`: server-local60.05s request is
rejected before effects;55s passes deadline validation and then receives the
expected missing-workspace refusal. Numeric server times and source hashes are
retained. This does not establish clock skew as the earlier failure's cause.

`review-live-02` additionally keeps a completed first HTTP response's sending
side open while a second actual command runs. The second succeeds and admission
stays open. Its lease test advances only the test frontend deadline BEFORE
dispatch, observes real registration, gets504/unknown, then proves the owner's
completed result and cleanup. It is explicitly not a900s elapsed-time soak.

## Retained failures and outcome separation

- red-lifetime-01: two expected failures in a deliberately deficient request-owned
  cancellation baseline. It is not a failure in the accepted Workspace and does
  not itself kill an actual frontend parent. Later real controls do.
- local-01: invalid test verifier schema, exit1. Fixed only the fixture.
- local-02: three refusal-response socket reset errors, exit1. Fixed bounded
  response half-close/disposal; no failures were deleted.
- review-red-01: three failures in the intermediate current source, exit1.
- review-baseline-red-01: immutable bridge SHA printed, five failing assertions
  covering both review defects and cleanup reserve, exit1. review-green-01 passes.
- application-01: stopped at disconnect after ten passed groups. Command execution
  was completed/success; normal delete remained unresolved after raw transport
  sequence49 returned `workspace_files.Refusal: deadline`. Separate recovery
  confirmed cleanup; original owner/execution records were not rewritten. Exit1,
  positive finally resource absence and unchanged shared5 retained. Lead directed
 55s+5s allowance; no measured clock-skew cause is claimed.
- review-live-01: supplementary test incorrectly changed the frontend deadline
  AFTER dispatch had captured its fixed wait. It returned owner_unknown as that
  unsupported test setup induced. Fixed only the test's setup ordering; exit1
  and positive cleanup/shared5 retained. review-live-02 passes.

## Limits and remaining work

Local doubles are not isolation proof. A socket write is not client receipt.
Neither owner exit nor cleanup confirmation reconstructs an unknown execution.
This bridge is not a Mo application profile, live-provider integration, full
machine-crash recovery, old-state adoption, or actual Mo E2E claim. No unconditional
900s execution/cleanup wall guarantee or full120s sustained command claim is made.

Machine work is complete and released. The authorized sequential compiler build
and test on the prior83 product both exited0: build38.125s/group89738 absent;
test415.260s/group90041 absent, 5/5 steps and243/243 tests passed. No machine or
compiler command was run for the subsequent IPC correction.

The retained ipc-fragment-red-01 reproduces the lead probe on prior83: HTTP200
completed at2.4104535s for a2s wait, admission open, exit1. The narrow correction
uses one monotonic deadline across IPC header/body reads and JSON completion,
and checks frontend completion before returning a result. Startup, owner lease,
tool wait and operator receives explicitly pass their existing deadlines. Owner
outcome persistence is unchanged. The identical probe in ipc-fragment-green-01
returns504/response_timeout/unknown at2.004961s with admission closed; exit0,
group95856 absent. Focused deadlines pass (group95720 absent), including valid
and incomplete fragmented frames, completed owner outcomes and confirmed cleanup.
The full corrected local matrix passes22/22, exit0,26.138s,group95992 absent.
All three new guards are bounded30/120s and evidence is below16MiB per attempt.
These are local subprocess/socketpair controls, not new real Workspace evidence.

SOURCE.json retains the prior83 identities and separately binds corrected bytes.
ATTEMPTS.json and EVIDENCE.json retain completed attempts and artifact hashes.
The correction is a separate commit; scope remains the owned bridge directory.
Independent lead verification and acceptance are not delegated to this report.
