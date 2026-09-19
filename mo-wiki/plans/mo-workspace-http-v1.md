---
title: "Mo workspace HTTP v1: six tools and retained ownership"
created: 2026-09-19
updated: 2026-09-19
type: plan
tags: [agents, tooling, verification, security]
sources: [plans/mo-workspace-recovery-v1.md, plans/mo-application-build-v1.md]
status: in-progress
---

# Mo workspace HTTP v1: six tools and retained ownership

## Purpose and ownership

Expose the accepted Python workspace's six operations to a later Mo application
profile. A request timeout must not abandon a running command. Recovery6266d293
is independently accepted (full243/243,5/5); actual lost-cleanup-response control
preserves unknown execution and confirms cleanup only on a separate invocation.
Read retained reviews in audit/evidence/2026-09-19/workspace-wire-readiness/:
compatibility-report.md, cleanup-review.md and application-budget-review-01.md.
Earlier missing long-command support is superseded by the accepted120s policy.

A fresh GPT-6-Astra worker at low reasoning owns ONLY new
`toolchain/harness/executor/workspace_http/`, including code, tests, docs and new
evidence. Python stdlib only. No core executor/recovery/application/provider,
Mo/compiler/generated IDs, wiki, image, policy or installed-input edits. Report
an actual ownership gap before edits outside this directory. Reuse Workspace
and recovery; do not fork the executor or reimplement filesystem containment.

You are not alone in the repository. Use the lead's exact clean base in a
separate worktree; preserve other work and all historical evidence. No nested
agents, push, rebase, downloads or shared Mac candidate execution. Every commit
must explicitly set GPT-6-Astra author AND committer. Every test/server/build
runs in an owned right/no-focus Herdr run pane under a numeric guard with
process-group cleanup. Never edit a running source/script. Retain failed attempts.

Local implementation/tests are released. Machine commands and full compiler
suite are gated until exact lead release. Dedicated machine is mo-executor-r01;
lead owns it now. No /opt, image, configuration or ceiling changes are needed.

## Operator and execution boundary

1. One run per listener, fixed127.0.0.1 ephemeral port. A trusted operator supplies
   run binding, source, result directory, selection and protected verifier before
   provisioning. Publish readiness only after creation succeeds. Generate a
   private256-bit capability token; every tool request needs its exact header.
   Keep token out of model context, Book, response errors and retained test logs.
2. A single serialized subprocess owns the Workspace from construction through
   cleanup. The frontend owns admission and bounded sockets; it never constructs
   a replacement Workspace. One admitted operation, no pending work queue.
   Limit live connections to4, backlog4, headers16KiB and32 fields; no unbounded
   ThreadingHTTPServer threads. Fixed deadline for incomplete request/write2s.
3. Keep owner lifetime independent of requests. Request timeout or an observed
   premature disconnect closes new admission, retains unknown response outcome
   and allows owner cleanup to finish. Frontend death must leave the owner able
   to finish/cleanup after IPC EOF; owner death permits explicit cleanup-only
   recovery once death is proved. Never steal a live owner lock or retry a tool.
   Successful local socket write is not proof the client received the result.
   IPC result delivery is bounded and never gates cleanup on frontend ACK. Close
   inherited pipe duplicates; terminal admission wins over every late result.
4. Persist private0700/0600 claims before effects: external run/workspace bindings,
   core32hex IDs, external call→core call mapping, payload hash and dispatch intent.
   Persist outcomes afterward, before notifying frontend. Repeated/conflicting IDs are refused,
   even if the previous response was lost. No cached-result replay or resume.
   Journal cap4MiB; reserve worst-case record space before dispatch, refuse when
   exhausted. Atomic replacement is sufficient; no fsync/crash-durability claim.
5. Persist the known ownership receipt path before the child's first remote
   effect. Retain original outcome separately from cleanup. Unknown transport
   or proof remains unresolved. Normal owner cleanup and constructor-free
   recovery use the accepted API/proofs; never infer success from process exit.
6. Operator-only start/freeze/verify/close controls use a private API/IPC boundary,
   not candidate HTTP routes. Close admission before freezing and protected
   verification. Candidate input cannot choose policy, machine, host paths,
   verifier commands, recovery records, lifecycle actions or other workspaces.

## Fixed wire contract

Use POST `/tool` only, no query/fragment. HTTP/1.1, exactly one canonical positive
Content-Length, no Transfer-Encoding, body≤851968 bytes; explicit response
Content-Length≤524288 bytes and Connection: close. Require application/json,
exact loopback Host with bound port, and no Origin. Do not enable CORS. Unsupported
method/path/headers/framing fail before dispatch. Bound parsing and socket writes.
Reject duplicate JSON keys, NaN/Infinity, unpaired surrogates, wrong types and
extra keys. Never treat booleans as numeric limits. Decode UTF-8 strictly.

Exact request keys: version, run_id, workspace_id, call_id, operation, args.
Version is `mo-workspace-http-v1`. Trusted external run_id is1..64 ASCII bytes
from `[A-Za-z0-9_-]`; workspace_id is operator-issued32 lowercase hex;
call_id is1..64 ASCII bytes from the same run-id alphabet. Bind all three and
validate before atomically claiming the call. The capability header is
`X-Mo-Workspace-Token`; no URL/body credential. Document the precise schema
and error enum in CONTRACT.md before final test evidence.

| operation | exact args | mapping/result |
|---|---|---|
| list_files | optional path, default `.` | Workspace.call list_files; items/truncated |
| read_file | path | Workspace.call read_file; text |
| search | query, optional path | query→core text; items with byte offsets/truncated |
| write_file | path, text | Workspace.call write_file; written |
| exact_edit | path, old_text, new_text | old_text/new_text→core old/new; edited |
| command | command, timeout_ms | Workspace.command with mapped call ID and seconds |

Use Workspace.call, not require, so refusals and execution metadata survive.
Keep existing file limits/controller65280-byte serialized cap; oversized core
results are explicit refusals, not silently successful truncations. Do not
promise every64KiB file is readable through escaped JSON. File truncation is
outer OR result.truncated. Preserve actual state/execution combinations;
timeout/cancel can accompany completed execution. Do not reuse the narrower
coding-fixture validator for these states.

Responses use one bounded envelope with version, bound identities (null before
validation), accepted, state, execution, error and result. Define exact enum and
nullable fields in CONTRACT.md. HTTP200 carries admitted tool outcomes;
400/401/403/404/405/409/413/415 cover malformed/unauthorized/unbound/unsupported/
conflicting/oversized requests;504 covers an admitted response wait that expires.
A pre-admission refusal has accepted=false/execution=not_started. Once effects
may have happened, a lost outcome is unknown; never relabel it not_started.
No traceback, host path, ownership document, manifest or supervisor observation
crosses HTTP. Preserve sanitized stable core errors and private raw evidence.

Command result: actual exit_code/signal (nullable), strict UTF-8 stdout/stderr,
encoding, execution_valid, combined truncated and elapsed_ms (nullable; floor
seconds×1000). Strictly validate base64 from core before decoding. Invalid text
returns explicit encoding failure and null text, preserving actual execution/
exit/signal; keep raw bytes privately. No replacement characters or fabricated0.

## Budgets and lifecycle

Fixed profile:16 admitted calls,900s admission lease from readiness,2s file
response wait,300s command response wait, candidate timeout_ms500..120000 integer.
Clamp candidate time to remaining lease before dispatch; insufficient minimum
refuses before effects. Use monotonic remaining budgets without resets. Lease
expiration closes admission and requests cleanup after the in-flight call. A
blocked owner cannot process cleanup concurrently; retain unresolved until proof.
The lease is admission expiry: later registration can establish a fresh candidate
deadline, so clamping is not an absolute execution-finish cutoff. Protected
verifier uses existing configured policy; no cleanup-within900s claim.
Separate cleanup attempt budget60s, retain unresolved if proof cannot be obtained.

Inherited locks, local I/O and launch prevent an unconditional finite synchronous
wall guarantee. Keep configured transport waits and independent runtime reapers.
An owner still alive after a frontend deadline remains responsible; a bounded
operator stop may target only the proved owned process, then use recovery, never
kill unknown holders. No automatic re-execution or old-state adoption. Document
what survives each process death and what requires an explicit operator action.

## Verification and done when

First retain real failing controls for the request/owner-lifetime gap before the
fix. Fix a registry of at most24 named groups before final evidence. Include:
all6 real tools; Unicode/binary output; schema/framing/byte bounds; identities and
capability; duplicate/conflicting calls; concurrent admission; file refusals;
command/lease deadlines; observed disconnect; frontend death; owner death; lost
response after effect; owner stall; startup failure; shutdown; protected verifier;
application binding; cleanup proof/unknown outcome; invalid selection. Related
scenarios may share a group. Unknown/empty/duplicate test selections fail before
output creation, listeners, owner startup or any machine dispatch.

After release, prove real HTTP against actual isolated Workspace for BusyBox
and application selection. Include actual parent death during a running candidate,
not only object deletion. Verify call execution counts and persisted intent order,
positive source/mount/container/service/cgroup absence, parent identity/effective
limits, five shared Mac Docker IDs/states unchanged. Use source/protected-verifier
canaries to prove no candidate access or local fallback. No actual Mo E2E claim.

Re-run inherited local59, workspace22/executor17/lifecycle1/application23 and
retain full zig build/test after the compiler gate release. Machine and full
compiler runs sequential. Keep strict raw transport capture for old regressions
using recovery/observe_regression.py; active exact slice readiness before dispatch.
Every live attempt≤1800s and≤16MiB evidence, all actual exits/source hashes/failures
retained, no unknown selection false pass. Build executable before native checks.

Freeze exact base/tip, actual attribution, clean worktree and reproducible guarded
commands. Report numbered decisions/limits, source/evidence manifest, named counts,
original execution versus cleanup outcome. Prove all owned groups/resources absent,
release machine explicitly, close only idle run panes; preserve worker worktree.
Lead reviews immutable diff, independently reruns plus an extra control, then
accepts. Receipt alone is not acceptance. Mo application profile follows separately.

## Related

- [[mo-workspace-recovery-v1]]
- [[mo-application-build-v1]]
- [[mo-first-coding-harness]]
