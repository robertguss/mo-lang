---
title: "Mo coding fixture v1: headless repair orchestration"
created: 2026-09-19
updated: 2026-09-19
type: plan
tags: [agents, tooling, verification, contracts]
sources: [plans/mo-first-coding-harness.md, plans/mo-provider-foundation.md]
status: complete
---

# Mo coding fixture v1: headless repair orchestration

## Orientation

Implement the first headless Mo coding path through the existing Agent.Run loop:
scripted command failure, inspection, exact repair, scripted command success and
a final answer, with recorded machine-readable results. This is an explicitly
trusted fixture profile. The command server treats command text as an inert
lookup key and never executes it. It establishes orchestration, not candidate
containment, a real build verdict, live inference or language value.

The read-only interface review is retained at
`audit/evidence/2026-09-19/coding-fixture-readiness/`. Astra chooses this bounded
slice under Robert's overnight authority. Provider and executor implementation
continue separately. Their future HTTP/workspace bridges are not present yet.

## Write scope

One fresh Astra/low Herdr worker, separate worktree at an explicit base, owns:

- New `examples/programs/agent/coding-fixture.mo`, `report.mo`, `exact-edit.mo`
  and `command-adapter.mo`.
- Only the integration needed in `examples/programs/agent/main.mo`, `run.mo`,
  `steps.mo`, `tools.mo`, `record.mo` and `registry.mo`.
- New `examples/programs/agent/tests/coding-fixture-v1/` for drivers, independent
  loopback fixtures, focused tests, evidence and README.
- `examples/programs/.mo.ids`, restricted to records for the above touched or
  new modules. Preserve all unrelated records exactly.

Actual `mo test --write` may also refresh verification lines and matching ID
records in dependent top-level Agent modules, with their existing simulation
coverage rerun. Record that exact dependency closure separately. This permits
generated evidence refresh only, not additional behavioral edits.

Keep Agent.Model behavior, its versioned recipe, shared recipes, Book/transcript schemas,
the compiler/PRELUDE, other applications, executor/provider code and wiki
unchanged. If a concrete dependency requires another source path, report it to
the lead before editing. No nested workers or push. Every Mo, server, build and
test process uses the repository guard and owned Herdr run panes. Capture failed
attempts and clean up owned descendants and loopback servers.

## Profile v1

Add the opt-in CLI command `coding-fixture`, preserving legacy CLI commands,
output/exit formats and behavior. The operator fixes the disposable fixture root,
model/command loopback endpoints and opaque workspace ID. The model can choose
neither an endpoint nor a filesystem root. Start the existing Book/Run machinery;
do not duplicate the loop or use Pi/Codex as the agent.

Reuse existing list/read/search/write tools only for trusted disposable fixture
files, separated from the running harness, compiler and result logs. Add an
explicit fixture tool catalog/grant path for `exact_edit` and `command` without
granting either to existing runs by default. The command is a fixture interface,
not an authorization to execute the text on the Mac.

Exact edit takes string arguments `path`, `old_text`, `new_text`. Require a
nonempty old text and exactly one literal occurrence, counting overlapping
occurrences as ambiguous. Preserve all other bytes. Missing/multiple matches,
denied grants, invalid paths and size violations leave the file unchanged.
Bound both original and resulting file to 64 KiB. Serialize read/check/write
through the existing Writer and a single caller-derived deadline. Do not claim
an atomic filesystem transaction or immunity to an outside concurrent writer.
A timed-out write is uncertain and is never retried automatically.

Command adapter v1 uses one POST `/fixture/v1/command` with JSON fields
`version` (1), `run_id`, `call_id`, `workspace_id`, `command`, `timeout_ms`,
`max_output_bytes`. The model supplies only the command string; the harness
owns identities and bounds. The response echoes version and identities, with
`state` (success/refusal/failure/timeout/cancellation), nullable integer
`exit_code`, string `stdout`/`stderr`, boolean `stdout_truncated` and
`stderr_truncated`, nullable nonnegative `elapsed_ms`, allowlisted `error_code`,
and `execution` (completed/not_started/unknown).

Success requires a complete matching response, completed execution and exit
zero. HTTP 200 is not success by itself. Nonzero exit maps to failure; malformed,
inconsistent, mismatched or oversized replies cannot pass. Never silently drop
truncation or coerce types. After dispatch, a transport failure has unknown
execution. Send once; do not retry. Record ordinary failure/refusal for the
model to inspect; timeout, cancellation and unknown execution terminate fixture
work after recording. They do not establish that a real command was killed.

Encode structured tool results into the existing tool-step result string as
JSON. Preserve the stored transcript schema and expose the structured value in
the new JSONL report. Existing tool outputs remain unchanged for legacy runs.

## Reporting and bounds

Emit JSONL after termination from recorded steps, followed by one recorded
terminal result. Live streaming is not required. Envelope fields are `schema`
(`mo-coding-fixture-v1`), `run_id`, `event`, `step_number` and `payload`.
Distinguish model, tool and terminal records. A transcript/report retrieval
failure emits an explicit reporting error and exits nonzero; never substitute
an empty successful transcript. Keep human diagnostics off the JSONL stream.

For fixture runs use at most 16 recorded steps, 4,096 reported synthetic tokens,
a 30-second run deadline and 2-second model/tool call caps, with zero model
retries. Cap serialized model requests at 64 KiB before every model call; stop
with `context_bytes` instead of silently compacting. This bounds bytes, not
tokenizer context. Retained command output is at most 64 KiB combined. Recording
and final reporting get one separate finite 15-second grace, with each wait
capped by its remaining time. Tests may lower bounds to exercise exhaustion.

Preserve Book.Write acknowledgement before subsequent model/tool dispatch.
Recording failure stops the run; uncertain effects are not replayed. Cancellation
is observed at the existing recording boundaries, not claimed as in-flight
executor cleanup. Capture each call's start before execution so elapsed fields
measure the operation. Correct only the timing plumbing needed for this profile.

Keep the model client's known-integer-token contract. Synthetic replies declare
their usage. Missing usage fails; failed-call usage is unknown in JSONL, and
tool usage is not applicable. Distinguish reported synthetic zero from unknown;
do not present a partial accumulated counter as complete provider usage. A
response may overshoot a token bound; stop subsequent work without claiming a
prepaid or exact billing cap.

## Checks and done when

At most 24 named behavioral cases per runtime, a ten-minute guard per attempt,
and 16 MiB retained evidence per attempt. No performance comparison. Demonstrate
the following in interpreter and compiled execution using trusted synthetic
loopback servers and disposable fixtures:

- Complete failure → read → exact repair → success path, with independently
  observed command/request order and every result recorded before subsequent
  work. Check the resulting bytes, JSONL states, identities and terminal record.
- Exact edit unique/missing/duplicate/overlap/empty-match, size/path/grant denial,
  and unchanged files after refusal.
- All command states, HTTP-200 nonzero exit, malformed/mismatched identities,
  truncation, bounds, finite timeout and exactly one command request.
- No further dispatch after step/token/context/deadline exhaustion, cancellation
  or recording failure; missing model usage reports unknown; declared zero stays
  reported. Simulated process checks where actually applicable.
- Existing Agent CLI fixtures, recipe conformance and transcript serialization
  still pass. Do not relabel skipped simulation as executed.

The worker reports exact base/tip, changed paths and ID records, commands,
counts, real exit codes, failed attempts and limitations. The lead reviews,
integrates and reruns checks with an extra control. Full native build/test
verification accompanies acceptance. Before any real model-generated candidate
or command trial, all workspace operations must share the isolated workspace
adapter with protected verdicts and verified command cleanup. That integration,
the provider HTTP bridge and actual candidate verification remain separate work.

## Filename correction — 19 Sep 2026, 1:10 AM ET

Worker checks 4 and 5 reproduced MO0323 for underscore filenames and MO0001
for underscore module names. The lead authorized `exact-edit.mo`,
`command-adapter.mo` and `coding-fixture.mo` in place of the original underscore
paths, with matching owned IDs. This follows the existing resolver convention;
module names remain Agent.ExactEdit, Agent.CommandAdapter and Agent.CodingFixture.
No compiler change or behavioral scope expansion. Failed checks remain in worker
evidence. The active write scope above reflects this correction.

## Result — 19 Sep 2026, 2:05 AM ET

Accepted integrated `e6f04ce6358c85f22a86f26be0b5b388495fcc6e`: worker
84d442e plus cold-runner correction 3964f1f. Lead verification passed 49/49
commands, seven cancellation controls, 22 HTTP cases per runtime plus two
boundary groups, all 12 exact legacy CLI goldens and six extra malformed-command
controls. Full integrated build/test passed 243/243 tests, 5/5 steps, exit 0.
All 3307 tracked toolchain/examples files stayed unchanged; owned groups closed.

Retained reds include the worker's own faults0 simulation tally failure, real
positive-17-token cancellation and native post-report append race. Final reports
wait for Run.Stopped and preserve per-call 17 while cancelled totals are unknown.
Lead cold verification found native fixtures ran before build and three missing
executable failures falsely passed. The correction builds first, requires an
executable and compares exact stderr, stdout and exit status. Lead attempt 02
started with the native executable absent. Historical evidence is unchanged.

Raw lead evidence/scripts: `audit/evidence/2026-09-19/coding-fixture/`.
Acceptance is trusted inert-command orchestration, not real candidate execution.
The actual provider-bridge Mo control is now released against exact e6f04ce.

## Related

- [[mo-first-coding-harness]]
- [[mo-agent-terminal-auth]]
- [[mo-executor-foundation]]
- [[mo-provider-foundation]]
