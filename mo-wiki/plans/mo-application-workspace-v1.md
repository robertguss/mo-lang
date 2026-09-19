---
title: "Mo application workspace v1: recorded remote tools"
created: 2026-09-19
updated: 2026-09-19
type: plan
tags: [agents, tooling, verification, processes]
sources: [plans/mo-workspace-http-v1.md, plans/mo-coding-fixture-v1.md]
status: planned
---

# Mo application workspace v1: recorded remote tools

## Orientation

Draft only: implementation release follows independent HTTP acceptance and an
exact integrated base. Extend Mo's existing Book/Run recording loop to the six
real isolated workspace tools. The separate scripted Logstat repair follows
this slice. No live provider/authentication or language-value acceptance here.
Read audit/evidence/2026-09-19/workspace-wire-readiness/application-profile-design.md
and application-budget-review-01.md, then accepted workspace_http/CONTRACT.md.

The lead owns decisions/integration/wiki/evidence; a fresh GPT-6-Astra low worker
in Herdr owns implementation in a separate exact-base worktree. You are not alone;
preserve others' changes. No nested agents, push/rebase, compiler/provider/core
executor changes, downloads, image/configuration/ceiling or /opt changes. Actual
commits must explicitly identify GPT-6-Astra as author AND committer. Retain all
failed attempts and do not edit a running source. Every test/build/server uses
an owned right/no-focus Herdr pane, numeric guard and owned group cleanup.

## Write scope

- New examples/programs/agent/application.mo and workspace-adapter.mo.
- Narrow application mode/configuration/dispatch/waits in agent/run.mo; explicit
  CLI branch in agent/main.mo; versioned application report entry in agent/report.mo.
- New examples/programs/agent/tests/application-workspace-v1/ for fixtures,
  Python/Mo controls, drivers, README and immutable evidence. No shared test edits.
- Actual generated verified/proven lines and aggregate .mo.ids records for these
  modules and their discovered dependency closure. Capture body/hash manifests
  before writes. Preserve unrelated records and dependent source bodies exactly.
  Use actual mo test --write and preserve sim100/5% fault metadata where inherited.

Book, Filing, Transcript, Model, Record, Budget/Order, Steps, Tools, Registry,
legacy fixture/command adapter and recipe bodies remain unchanged. No new syntax,
compiler fix, fake generated hash or copied executor implementation. Report a
concrete ownership gap with source evidence before crossing these boundaries.

## Parts

### One explicit operator mode

Add opt-in CLI `application-workspace` with disposable operator Book root, goal,
loopback scripted model endpoint and bounded private workspace-config path.
Existing serve/run/check/mock/client/coding-fixture parsing and outputs stay exact.
Use one versioned Config type; no ambient credentials or general mode framework.

Trusted config contains fixed HTTP version,127.0.0.1 port, external run ID,
workspace32hex identity and capability64hex token. Operator provisions0700 parent/
0600 file outside Book and candidate. Mo bounds contents to4096 bytes and validates before Begin;
this is trusted local provisioning, not a new hostile-local-file security claim.
Keep token out of argv, model requests, goals, Book, reports, exceptions and test
logs. Retain hashes/source identity without printing the capability. No token flag.

Use a fresh Book root with work/ placeholder. Open must prove no previous runs or
restart before Create. Book.Create remains authoritative; require Made.record.id
matches the configured external run binding before Configure/Begin/HTTP. Fresh
Book currently starts r_1; do not override IDs, adopt old runs or parse Book in
Python to make product binding work. Tests may independently inspect its bytes.

Start Run directly with writer=None and read-only placeholder scope. Configure
application once while Ready, mutually exclusive with fixture mode. Treat a false
configuration reply as failure. All six tools route remotely before local Tools;
use conflicting operator/candidate canaries to prove zero local fallback.

### Explicit budgets and one stable record order

Keep serialized Budget/Order shapes:16 steps,4096 synthetic tokens,wall900000,
retries0,tool2000, fixed six grants. Do not broaden legacy order validation.
One outer900s includes startup, work and reporting. Derive Begin's work deadline
from remaining minus15000ms reporting reserve, refusing if exhausted. Preserve
Run's existing shared diminishing grace accounting, not a fresh15s each write.

Model/file waits<=2000ms. Command response wait<=300000ms, requested candidate
execution<=120000ms, independently clamped to remaining work time. Refuse before
dispatch below500ms candidate minimum. Model cannot supply endpoint, IDs, token,
policy, runtime timeout or verifier. Trusted adapter derives those fields. The
next Book step number identifies the HTTP call. Keep model args unchanged in Book.

Validate grant, exact operation args and encoded byte bounds before HTTP. Follow
all six accepted mappings: list_files/read_file/search/write_file/exact_edit/
command. No retry or cached-result replay. Once a call might have happened,
transport failure is unknown. Record every observed outcome once before any
later model/tool call; a failed write acknowledgement stops further dispatch.

### Bounded HTTP projection

Use existing Http.send framing (HTTP/1.1, Host:port, Content-Length, close) and
private capability header. Enforce accepted request851968/response524288 bounds,
exact envelope keys/version/identities/types/enums, per-operation result shape,
nullable fields, combined truncation, true exit/signal and elapsed_ms. Reject
invalid/ambiguous JSON according to available proven parser behavior; report an
actual parser limitation rather than inventing syntax or claiming a missing check.

Preserve completed refusals and timeout/cancellation with completed execution.
A valid failed command with completed execution and exit1 is repair feedback and
may continue. Unknown execution, invalid execution proof, invalid body/binding,
lost acknowledgement or closed admission stops new dispatch. Classify refusal
from fields, never stdout substring. No fabricated exit0, replacement text,
private manifest/observation, host path or core exception crosses into model data.
Keep controller result_too_large and output_encoding facts; do not pretend every
64KiB file fits its escaped JSON response. Freeze this mapping before final runs.

### Deadline-driven completion and reports

Use the existing deferred Reply pattern in processes/deferred-reply.mo: retain
Start's reply unconditionally, schedule bounded delayed self-polls, answer once,
retire held reply and stop scheduling. No2250/45000 iteration proxy for a deadline.
Startup failures must answer the retained reply too. Prove behavior with actual
compiler/native/simulator controls; no new process or reply semantics are assumed.

Wait for terminal Book AND Run.Stopped, then acquire remaining ReportDeadline and
reread final record/transcript. Keep the cancellation rule: terminal usage unknown/
null even if recorded calls have positive synthetic tokens. Do not mutate Book
or append after the report. Stopped proves Mo dispatch ended, not external cleanup.
The operator separately freezes/verifies/closes or explicitly recovers the owner.

Version report schema `mo-application-workspace-v1` and include fixed profile caps
so the unchanged legacy header cannot hide extended command waits. Keep legacy
report bytes exact. Reuse narrow report logic where practical, without duplicating
the whole report or creating a configurable reporting subsystem.

## Numbers and verification

Fix <=24 named acceptance groups before final evidence. Local source/fixtures
first; machine and full compiler remain gated until explicit lead release.
Each attempt<=1800s and<=16MiB retained evidence, actual exits, raw bounded
transport, immutable sources, positive process/resource absence, shared5 unchanged.
Never run machine workloads concurrently with a full compiler suite.

Required interpreter AND compiled controls: all six actual remote tools and
on-disk Book prefix before every model/tool dispatch; failure->read->exact-edit
->successful command->answer; distinct waits/candidate cap/near-expiry/reserve;
configuration/grant/schema/encoding/body-bound/identity negatives; unknown/lost
outcome stops; completed refusal and failed command handling; token absence and
operator canaries; fresh-root refusal; unchanged operator placeholders.

Real cancellation during command collection must retain any eventual recorded
per-call usage, terminalunknown/null, no subsequent dispatch and no Book append
through a300ms post-report window in both runtimes. Poller startup error/normal
completion/deadline must each answer once and stop scheduling. Scheduling controls
use actual sim100/5% faults, with inherited invariant metadata preserved.

Preserve12 exact legacy CLI goldens, coding-fixture22-case matrices each runtime,
its cancellation controls, terminal-auth interpreter/native9 each, relevant
model/recipe tests, all actual generated dependency checks/builds and formatter
checks. Build the current native executable before native cases and reject absent
or invalid executables before dispatch. Full zig build and test --summary all
follow final frozen source and machine cleanup; all failures remain retained.

## Done when

Freeze clean exact base/tip, explicit Astra attribution and source/ID/evidence
manifest. Report numbered decisions/limitations and exact reproduction commands,
selected counts and actual outcomes versus cleanup proofs. Release machine and
close only idle run panes after process proof; preserve worktree/worker for review.
Lead immutable review, independent integrated reruns and extra control determine
acceptance. Then a separate Logstat repair brief tests the complete workflow.

## Related

- [[mo-workspace-http-v1]]
- [[mo-coding-fixture-v1]]
- [[mo-first-coding-harness]]
