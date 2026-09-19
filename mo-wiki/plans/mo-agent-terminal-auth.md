---
title: "Agent terminal authentication policy v1"
created: 2026-09-19
updated: 2026-09-19
type: plan
tags: [agents, errors, verification, contracts]
sources: [plans/mo-first-coding-harness.md, spec/programs/05-agent-harness.md]
status: complete
---

# Agent terminal authentication policy v1

## Orientation

Bounded application policy change under Robert's overnight authority, chosen by
the Astra lead. It is preparation for the 401 workflow calibration in
[[mo-first-coding-harness]], not a scored agent experiment or evidence of
language value. The shared model-client recipe currently retries non-200
statuses. Its current behavior is therefore not a violation of that recipe.

## Policy v1

For one `Agent.Model.complete` call, an HTTP 401 response is terminal: return
`Error(Status(code: 401))` and make no further model request in that call.
Do not attempt provider login or credential refresh in this function. Preserve
all other retry classifications, the `retries + 1` upper bound, request/reply
shapes and caller-derived deadline behavior. A deadline already exhausted
before the call makes zero requests. A transport timeout remains `Late`.

This is an Agent-specific specialization. Leave
`examples/recipes/model-client.mo` and its existing generic policy unchanged.
Introduce `Recipes.AgentModelClientV1.ModelClient` in
`examples/recipes/agent-model-client-v1.mo`, retaining the generic recipe's
body/parser, attempt-limit and deadline contracts/tests and adding the terminal
401 policy and real-status tests. Bind Agent.Model to this new recipe.
The versioned recipe makes the changed promise explicit; it is not an exemption
from the old promise while still claiming generic recipe conformance.

The policy section is version 1 at the brief's first commit. Any subsequent
behavior change gets a new version and decision row; Result/status updates
do not amend the policy.

## Write scope

One fresh Astra/low worker in a separate Herdr worktree owns only:

- `examples/programs/agent/model.mo` and only its Agent.Model record in
  `examples/programs/.mo.ids`.
- New `examples/recipes/agent-model-client-v1.mo` and only its new module record
  in `examples/recipes/.mo.ids`.
- New `examples/programs/agent/tests/terminal-auth/` for the smallest status
  driver, independent HTTP fixture and test outputs needed for this unit.

No other Agent features, shared recipe changes, compiler/PRELUDE edits, live
provider calls, credentials, other application code or historical evidence.
If the recipe runner requires another concrete path, report that dependency
to the lead before changing it. The lead owns this policy and acceptance.

### Generated dependency closure, 19 Sep 2026, 12:52 AM ET

Lead full-suite verification after integration returned 241/243: dependent
Agent modules rejected stale verification records (MO0317), and the new driver
lacked a generated verification line. The focused 18-case matrix and six extra
lead controls passed, but acceptance is open. Raw failure:
`audit/evidence/2026-09-19/agent-terminal-auth/native-suite.stderr.txt`.

The lead authorizes actual `mo test --write` regeneration for Agent `tools.mo`,
`steps.mo`, `run.mo`, `registry.mo`, `server.mo`, `check.mo`, `main.mo`, `runs.mo`
and the owned terminal-auth driver. Only their toolchain-generated verification
lines and exact records in `examples/programs/.mo.ids` may change; no behavior
edits. Preserve prior simulated-run coverage by rerunning those checks, not
downgrading the record. Keep previous ID diffs/evidence immutable and add a new
scope report. This is the concrete dependency closure required by the versioned
model change; policy v1 and the shared recipe remain unchanged.

## Parts and checks

1. Add tests that send actual HTTP statuses and independently count received
   requests. Show the old implementation violates the proposed terminal policy.
   A JSON body merely containing 401 is not a status test.
2. Add the versioned recipe and make the smallest Agent implementation change.
   Preserve generic behavior tests; do not alter the retry loop beyond the
   terminal condition needed by this policy.
3. Run recipe conformance and focused tests, then both interpreter and compiled
   driver against the independent fixture. The lead repeats them after
   integration and adds a control the worker did not choose.

For `retries=2` unless specified, the fixed acceptance inventory is:

| response sequence or condition | requests | outcome |
|---|---|---|
| 401, followed by a valid reply that must not be requested | 1 | Status(401) |
| 503, 401, followed by a valid reply | 2 | Status(401) |
| malformed HTTP-200 body, 401, followed by a valid reply | 2 | Status(401) |
| 503, valid HTTP-200 reply | 2 | successful reply |
| three 503 responses, followed by a valid reply | 3 | Status(503) |
| valid HTTP-200 reply | 1 | successful reply |
| deadline exhausted before starting | 0 | Late |
| response delayed beyond a finite caller deadline | 1 | Late; no retry after deadline |
| retries=0, 401 | 1 | Status(401) |

All test processes run under `toolchain/bench/step36/guard.py` with finite
timeouts and in owned Herdr run panes. The HTTP fixture binds only loopback on
an ephemeral port and shuts down after the test. No model credentials or live
inference. Keep real exit codes and failed attempts. A full attempt has a
10-minute outer limit; each HTTP operation has a deadline.

## Done when

All nine behavioral cases pass with observed request counts in both execution
modes, recipe checks pass, the generic recipe is byte-identical to its base,
and the diff stays within the allowlist. Report actual commands/counts and
any untested obligation. No dependency on the new executor's readiness is
claimed: these are trusted local fixtures testing the application client,
not untrusted coding-trial candidates.

## Result — 19 Sep 2026, 1:19 AM ET

Accepted after independent integrated-tree verification. Worker commits through
`ebbf86c` are integrated through `e3a01bb`. The implementation specializes
Agent.Model's 401 behavior and binds the new versioned recipe; the shared
`model-client.mo` remains byte-identical with its nine inherited tests preserved.

| Evidence | Result |
|---|---|
| Real baseline red | 401 followed by an unexpected second request and Answer(7,5); runner exit 1 |
| Lead nine-case matrix | interpreter 9/9 and compiled 9/9; request counts 1,2,2,2,3,1,0,1,1 |
| Extra lead controls | both runtimes: 403/429 still recover; valid-JSON 401 body remains Status(401), 6/6 |
| Model/conformance/generic | 3/3 model; 16/16 versioned with three signatures; 9/9 inherited tests |
| Generated dependency closure | eight unchanged dependent source files; only recorded Model dependency hashes changed, prior sim100 retained |
| Formatter closure | three files match actual formatter output; one driver ID record's two hash fields regenerated |
| Final lead full native suite | build exit 0; 243/243 tests, 5/5 steps, exit 0; no remaining owned process groups |
| Final source comparison | all 62 changed auth files match reviewed worker tip; generic recipe unchanged |

The initial full-suite failures remain: 241/243 before dependency closure, then
242/243 before formatter output. Final full suite ran at `e3a01bb`, 1:09–1:17 AM
ET. Earlier lead matrix/extra controls ran before generated-only/formatter
corrections; the worker repeated six focused status/deadline cases after the
formatter, and the final full suite covers the integrated result. No unreported
matrix rerun is implied. Standalone recipe source reports one test and 15 skips;
actual conformance against Agent.Model executes all 16. Model-only `--sim`
reports simulation not run; the 100-seed claims apply to actual dependent process
tests, not that command.

Raw lead scripts, all three attempts, six extra controls and exact final identity
are under `audit/evidence/2026-09-19/agent-terminal-auth/`. This calibrates the
versioned local policy; it does not establish live provider behavior, an isolated
candidate repair, language value, Step 39 or Program 7 acceptance.

## Related

- [[mo-first-coding-harness]]
- [[05-agent-harness]]
- [[decision-log]]
