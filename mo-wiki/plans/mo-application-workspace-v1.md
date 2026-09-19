---
title: "Mo application workspace v1: recorded remote tools"
created: 2026-09-19
updated: 2026-09-19
type: plan
tags: [agents, tooling, verification, processes]
sources: [plans/mo-workspace-http-v1.md, plans/mo-coding-fixture-v1.md]
status: done
---

# Mo application workspace v1: recorded remote tools

## Rebuild from scratch, 19 Sep 2026, 7:20 AM ET

Robert and the Fable lead decided ([[decision-log]]) to discard Astra's
unfinished attempt and rebuild this slice from accepted base `030290b8`. The
attempt (checkpoint `0a74a0fc`, WIP `0b1404b5`, branch
`harness/application-workspace-v1`) is historical evidence: do not merge, copy
from or edit it. The worker is a fresh Claude Opus session on branch
`harness/application-workspace-v2` in worktree
`~/Projects/startups/mo-lang-worktrees/harness-application-workspace-v2`.
Everything below stands except where this section differs.

**Findings the rebuild must close, RED first.** Each gets a failing control
committed before its fix, in both runtimes. Read the four reviews under
`audit/evidence/2026-09-19/application-workspace/` for the exact bodies.

1. A pre-admission refusal with null identities (HTTP 401, `not_started`) keeps
   `not_started`; it must not become `invalid_response/unknown`. Stopping is fine.
2. HTTP status is checked against the contract for unaccepted responses too: a
   `busy` refusal on HTTP 500 is a contract violation, since busy is 409.
3. A command result's streams are both strings, or both null with
   `failure/output_encoding`. A success with null output, or mixed null and
   string, is rejected.
4. `state=success` with a nonzero exit code is rejected. Do not add a
   signal-null condition; the producer does not establish one.
5. Near-expiry: the candidate timeout is taken after request encoding, or the
   matrix proves that time spent encoding a large request cannot dispatch
   below the 500 ms minimum.
6. Evidence never adds `.mo` files under `examples/`: `corpus.zig` collects
   every `.mo` file and would run saved copies and deliberate failures as
   corpus entries. Keep source copies as non-`.mo` artifacts with a path and
   SHA mapping; failing controls live where the corpus does not read them.
7. The guard wrapper records the child's actual return code separately from
   its own outcome and reason; a synthetic 124 never replaces an observed exit.

**Proportionate evidence.** Per attempt keep the command, real exit code,
summary line and failing output. No per-run process tables or full
source-identity manifests; one source manifest at the final freeze. The whole
slice's retained evidence stays under 2 MiB, replacing the 16 MiB-per-attempt
allowance below. Commits are authored by the worker as itself, with a
`Co-Authored-By` line naming its model; the Astra attribution rules below do
not apply.

## Orientation

Released for local implementation after HTTP acceptance atcf99cd88; the lead
supplies the exact checkout base. Extend Book/Run's recording loop to the six
real isolated workspace tools. The separate scripted Logstat repair follows
this slice. No live provider/authentication or language-value acceptance here.
Read audit/evidence/2026-09-19/workspace-wire-readiness/application-profile-design.md
and application-budget-review-01.md, then accepted workspace_http/CONTRACT.md.

The lead owns decisions/integration/wiki/evidence; a fresh Claude Opus worker
in Herdr owns implementation in a separate exact-base worktree. You are not alone;
preserve others' changes. No nested agents, push/rebase, compiler/provider/core
executor changes, downloads, image/configuration/ceiling or /opt changes. Retain all
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
0600 file outside Book and candidate. On this trusted stable file, check fs.size
before fs.read and returned byte_size<=4096 before Begin. This is an acceptance
limit, not an atomic read/allocation bound or hostile-local-file security claim.
Keep token out of argv, model requests, goals, Book, reports, exceptions and test
logs. Retain hashes/source identity without printing the capability. No token flag.

Use a fresh, exclusively operator-owned Book root with work/ placeholder. Before
Book.Open, inspect its runs directory and refuse any existing artifacts, including
empty/truncated or unrecognized logs. Ready(0,0) alone is insufficient and Open can
append restart records. Retain that check after preflight. Book.Create remains
authoritative; require Made.record.id
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
private capability header. Enforce encoded request851968 and received body524288
acceptance limits before JSON decoding. Http.send retains its existing1MiB body/
3MiB+8 connection-buffer limits;524288 is not a transport allocation bound. Check
exact envelope keys/version/identities/types/enums, per-operation result shape,
nullable fields, combined truncation, true exit/signal and elapsed_ms. Reject
invalid/ambiguous JSON without changing the compiler. Json.decode rejects grammar,
nonfinite numbers and unpaired surrogates, but silently collapses duplicate keys.
After successful decode, count raw colons outside quoted strings (correct escape
parity) and compare with recursive Object member counts through ALL arrays/objects;
any mismatch refuses duplicates, including escaped-equal keys/discarded subtrees.
Require integer lexical tokens (no fraction/exponent), then to_i64 and field ranges;
all versioned numeric fields are integers/null. Test both runtimes, including
quoted colons, even backslashes, nested duplicates and rounding-edge negatives.
Read application-json-api-review-01.md and application-json-strict-review-01.md
under the readiness evidence directory; source feasibility is not compiled proof.

Preserve completed refusals and timeout/cancellation with completed execution.
A valid failed command with completed execution and exit1 is repair feedback and
may continue. Unknown execution, invalid execution proof, invalid body/binding,
lost acknowledgement or closed admission stops new dispatch. In Run recording,
apply the application adapter terminal decision after the successful write for
ALL six tools; existing fixture command/exact_edit logic alone is insufficient.
Keep that legacy path exact. Classify refusal
from fields, never stdout substring. No fabricated exit0, replacement text,
private manifest/observation, host path or core exception crosses into model data.
Keep controller result_too_large and output_encoding facts; do not pretend every
64KiB file fits its escaped JSON response. Freeze this mapping before final runs.

### Deadline-driven completion and reports

Use the existing deferred Reply pattern in processes/deferred-reply.mo: retain
Start's reply unconditionally, schedule bounded delayed self-polls, answer once,
retire held reply and stop scheduling. No2250/45000 iteration proxy for a deadline.
Startup failures must attempt the retained reply too; distinguish at-most-once
answer invocation from caller receipt when its deadline has expired. Prove with actual
compiler/native/simulator controls; no new process or reply semantics are assumed.

A successful terminal report requires terminal Book AND Run.Stopped. Ask
ReportDeadline using the retained OUTER deadline (not a fresh2s cap), then share
the returned deadline across final record/transcript reads. If Run stopped but
Book remains Running or unavailable, return explicit versioned reporting_error,
never a fabricated terminal result; request no further writes. An earlier
unacknowledged Book write remains uncertain, not proof of an immutable log. Keep the cancellation rule: terminal usage unknown/
null even if recorded calls have positive synthetic tokens. A successful terminal report must not be followed by a Book append; distinguish
that proved outcome from reporting_error with uncertain earlier persistence. Stopped proves Mo dispatch ended, not external cleanup.
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

Freeze clean exact base/tip and one source/ID/evidence manifest. Report numbered decisions/limitations and exact reproduction commands,
selected counts and actual outcomes versus cleanup proofs. Release machine and
close only idle run panes after process proof; preserve worktree/worker for review.
Lead immutable review, independent integrated reruns and extra control determine
acceptance. Then a separate Logstat repair brief tests the complete workflow.

## Result

Rebuilt by Claude Opus 5 and accepted 19 Sep 2026, 9:03 AM ET, at the level shown: local controls in both runtimes and the real Bridge front end; full suite 243 of 243. The end-to-end machine run is owed by the Logstat slice ([[decision-log]]).

## Related

- [[mo-workspace-http-v1]]
- [[mo-coding-fixture-v1]]
- [[mo-first-coding-harness]]
