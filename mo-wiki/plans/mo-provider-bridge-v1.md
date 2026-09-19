---
title: "Mo provider bridge v1: native history and recorded continuation"
created: 2026-09-19
updated: 2026-09-19
type: plan
tags: [agents, tooling, verification, security]
sources: [plans/mo-provider-foundation.md, plans/mo-coding-fixture-v1.md]
status: complete
---

# Mo provider bridge v1: native history and recorded continuation

## Orientation

Next bounded offline integration under Robert's overnight authority. Adapt the
accepted provider-only turn to the existing Mo `/complete` contract, preserving
Pi's native conversation separately from Mo's recorded projection. Do not build
another tool loop. [[mo-provider-auth-v1]] owns credentials; this bridge receives
an explicit in-memory access token and trusted transport, with no login/store
lookup or refresh-on-401. No live inference is authorized in this slice.

The bounded source review at
`audit/evidence/2026-09-19/provider-bridge-readiness/worker-report.md` identifies
the missing native IDs/signatures and acknowledgment limits. A trusted Run sends
its next request only after Book.Write acknowledgment. The bridge can validate
that transcript continuation, but cannot independently prove a Book disk write
against a forged caller. Do not label the final offered answer Book-recorded.

## Ownership and prerequisites

One fresh GPT-6-Astra/low worker, separate exact-base worktree, no nested agents.
Own only new `toolchain/harness/provider/bridge/`, including tests, runner,
README and new evidence. Freeze foundation/auth/Agent/compiler/executor/wiki
files and all historical evidence. No packages, pin, patch or catalog changes.
Actual Astra author/committer, local commits only; no worker push/rebase.

Reuse exact pinned provider source/preparation in a fresh owned ignored copy.
Keep source/artifact mismatch and actual runtime identity in the report.
All Node/Mo/tests/servers use numeric guards and owned process-group cleanup in
a right/no-focus Herdr run pane. No machine or shared Mac Docker commands.
Bridge-only fixture work may proceed now. The lead explicitly releases the
real Mo end-to-end control after coding-fixture integrated acceptance; preserve
that dependency while continuing server/journal work independently.

## Frozen protocol

One operator-provisioned run per process, bound to a fresh random session ID,
explicit expected run ID (including the legacy r_1), goal and ordered grants.
Listen only on 127.0.0.1, caller-selected ephemeral port. No dynamic registration,
remote client support or tool execution. Loopback is not client authentication;
the caller/host and provisioning API are trusted. No secret CLI arguments.

Accept only POST `/complete`, JSON content type, exactly one matching x-run
header and `{goal, tools, transcript}`. First transcript must be empty. Freeze
the exact goal/grants and reject foreign identity, changed grants/goal, skipped,
stale, altered or duplicate history. Read limits apply while streaming, including
chunked requests. Handle malformed JSON/types, disconnects and slow bodies.

Bridge owns fixed object schemas with string arguments and no extra fields:
list_files(path), read_file(path), search(path, query), write_file(path, text),
exact_edit(path, old_text, new_text), command(command). Require these arguments
explicitly even where legacy tools have defaults; filter by frozen grants and
reject unsupported/duplicate grants. Supply precise descriptions and a fixed
system instruction identifying the trusted tool boundary. Do not stringify or
coerce model arguments. Use only the foundation's exact one-tool/final result.

Return the unchanged Mo shapes `{tool, args, tokens}` or `{done, tokens}`.
Successful tokens use provider-reported total once, a nonnegative safe integer;
reported zero is valid. Unknown/incomplete usage terminally fails with sanitized
HTTP 422 before exposing a tool or answer. Do not manufacture zero or infer
usage from Pi's normalized native message. Mo must use zero retries, as in the
fixture profile. HTTP 401 remains 401 and terminal; other provider errors also
terminalize this run. No upstream retry, refresh or alternate model.

## Native history and acknowledged continuation

Construct native initial context from the frozen goal/instruction/schemas.
Retain each successful complete AssistantMessage unchanged, including all IDs,
signatures and reasoning metadata. Never reconstruct it from Mo's transcript.
For the next request, accepted prefix must be byte-equivalent at the JSON value
level and exactly two consecutive new steps must appear: the offered model
tool step and its matching tool result. Validate every step field/type, numbers,
model name/empty args, model result projection, exact reported tokens, matching
tool name/args, zero tool tokens, nonnegative elapsed and refusal boolean.

Use the original complete Pi toolCallId to create the native ToolResultMessage.
Preserve the result string, including structured command/edit JSON. For those
two structured tools, validate state/execution and map failure/refusal/timeout/
cancellation to isError; ordinary legacy tools use the recorded refusal flag.
Never classify a result by finding an error word inside its stdout/text.
Terminal or uncertain command/edit outcomes cannot continue inference.

Persist the validated continuation before dispatching its next provider call.
Reject concurrent calls without queuing. Duplicate/conflicting requests for this
run cannot receive a cached actionable response or cause a second upstream call;
terminalize ambiguity, abort any active call and suppress its late action.
Final answer state is final-offered and never reusable for another dispatch.

## Journal, limits and termination

Use one explicit absolute private journal path in a trusted directory outside
candidate storage. Refuse unsafe/symlink paths and existing files. Record the
version, session/run, fixed provider/catalog/schema/config identity, accepted
prefix, offered projection, native messages, per-call usage and outcome.
Never record credentials, request authorization headers or raw provider errors.
Content and native history are private task data; do not print them by default.

Write dispatch intent before calling provider. Persist native result/projection
before HTTP reply. Use bounded atomic same-directory snapshot replacement with
one writer; no crash-durability claim. Journal failure stops dispatch. Lost reply,
disconnect, timeout or ambiguous persistence becomes terminal/uncertain with no
action replay. Late completions cannot return an actionable reply or overwrite
the terminal decision. Restart with any prior journal/tombstone, even truncated
or malformed, refuses rather than resumes. Retain terminal state; no garbage
collection or automatic reset in this slice.

One active request; 16 recorded Mo steps; 4096 accumulated reported tokens;
30-second session; 64 KiB request/reply/native context; 2 MiB journal. The
reported-token cap stops later calls after an overshoot and is not a billing
guarantee. Body/provider/reply waits cap at two seconds under session remaining;
closing journal/response work has one separate finite 15-second grace. Enforce
actual encoded bytes and finite deadlines, without compaction or silent drop.
Stop aborts inference, closes listener/sockets and suppresses late actions; it
does not prove upstream cancellation or executor cleanup.

## Done when

At most 28 fixed named controls, each attempt guard 600 seconds and retained
evidence at most 16 MiB. Reject unknown/empty selections. Keep every failure,
exact commands, real exits, request counts/order, source hashes and cleanup.

Use actual pinned parser with synthetic HTTP/SSE transport, deny all external
egress before loading provider code, and close every listener/socket/process.
Cover final; tool continuation; native IDs/signatures; schema/argument rejection;
reported zero/unknown/overflow/overshoot; duplicate/stale/conflicting/skipped/
mismatched steps; changed goal/grants/identity; concurrent request; existing or
corrupt journal; write failure; dropped reply; 401/other failure; session/body/
provider deadline; stop/disconnect/late completion; byte/journal/context limits;
structured tool errors and literal error words; sanitized secret canaries.

Reserve one control for actual Mo end-to-end after lead release: synthetic
provider tool call -> Mo recorded model step -> inert HTTP command fixture ->
recorded tool step -> matching native continuation -> final answer. Independently
read Book's on-disk steps before each later HTTP dispatch, count provider calls,
and retain native ID/signature replay evidence. Run interpreter and compiled
variants in that group. No candidate command executes on Mac.

Unchanged foundation 28-case regression must pass from a fresh prepared copy.
Lead reviews the immutable patch and repeats tests plus an independent control.
No live account, executor, application-repair or language-value claim follows.

## Result — 19 Sep 2026, 2:32 AM ET

Accepted integrated `191da144809a83ecadd1902aadd6507e898fa31b`: worker c17d65a
and separate mixed-selection correction 9e2feb8e. Lead exact 92-file comparison,
fresh-copy 27 independent groups, actual Mo in both runtimes, unchanged28-case
foundation and two extra HTTP controls pass. Each Mo run has two pinned-parser
provider calls, one inert command and three Book steps, independently read from
disk before dispatch. Native IDs/signatures survive continuation.

Full integrated build/test passed 243/243 and 5/5; 3489 tracked toolchain/examples
files unchanged during recorded verification. All 278 provider files in main and
copy are unchanged; owned groups/listeners closed. Retained failures include
missing Content-Length found by real Mo, and valid mixed selection lacking Mo
preparation. Correction uses actual selection membership, with negative tests
rejecting before copying/Node. Exact commands and raw outputs are under
`audit/evidence/2026-09-19/provider-bridge/`.

Trusted operator enforces once-per-production-process provisioning; the library
is one run per listener, with no global singleton. No live auth/inference,
real executor command, application repair, crash durability or client-receipt
claim. Worker is idle and its owned panes are closed.

## Related

- [[mo-provider-foundation]]
- [[mo-provider-auth-v1]]
- [[mo-coding-fixture-v1]]
- [[mo-first-coding-harness]]
- [[decision-log]]
