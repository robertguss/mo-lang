---
title: "Overnight harness continuation — 19 Sep 2026"
created: 2026-09-19
updated: 2026-09-19
type: session
tags: [agents, tooling, verification]
sources: [plans/mo-workspace-recovery-v1.md, plans/roadmap.md, decisions/decision-log.md]
date: 2026-09-19
session: 13
---

# Overnight harness continuation — 19 Sep 2026

Robert authorized Astra to keep deciding and working while he sleeps, with
fresh Astra workers at low reasoning in Herdr. Earlier accepted foundations
are recorded in [[session-05]] and CHANGELOG.md; this page continues the account.

## Recovery accepted, 4:27 AM ET

[[mo-workspace-recovery-v1]] now supports explicit cleanup after owner loss,
including lost reservation responses and late bootstrap. The lead reviewed
immutable source, reproduced proof/schema gaps and independently ran local59,
21 extra schema controls, recovery16, workspace22/executor17/lifecycle1/app23
and an actual post-effect lost-response control. Full243/243,5/5 passed.
All11128 tracked files unchanged;84 execution resources/57 workspaces/76 actual
cgroups absent; both parent task sets empty and shared5 containers unchanged.

Historical malformed transport and TLS failures remain unexplained. Later
missing slice hierarchy was a separate readiness error corrected by activating
existing unchanged units. Each of two operator cases remains14 API-confirmed/
1 API-unresolved despite proved physical cleanup. No whole-machine recovery or
execution replay. Worker6266d293 is integrated throughde71578d; worktree preserved.

## HTTP review and correction, 5:18 AM ET

Worker83a72dd4 corrects completed-response drain closure and deadline status,
with real22/22 on both workspace profiles and inherited runtime regressions green.
Application's first cleanup refusal remains retained;55s delete plus5s transport
fits the configured60s allowance. Numeric controller validation is measured,
without attributing the original failure to clock skew. Machine is released,
compiler build passed and full test is active sequentially.

Lead independently reproduced both drain failures on75680 and both passes on83a72.
A further fragmented-IPC probe returned200/success at2.413s for a2s file wait:
recv resets its timeout per chunk. Narrow correction is assigned after the active
compiler finishes. All failed attempts remain; HTTP acceptance is still pending.

At5:31 AM ET the worker full suite has passed243/243,5/5 in415.26s. The exact
fragmented-IPC failure was reproduced again, and ordinary local correction is
underway. A platform Daybreak-unavailable notice was recorded; no rejected tool
operation was identified, no model change or security tool was used.

A fresh Astra/low read-only review of the Mo draft found four source-backed
clarifications: preflight the exclusively owned runs directory before Book.Open;
apply terminal classification to all six tools after recording; distinguish
stopped-but-unsettled reporting_error; request ReportDeadline under the retained
outer deadline. Draft updated; reviewer pane closed after its idle proof.

## HTTP accepted, 6:38 AM ET

Worker42015b73/product1cf268b3 is integrated unchanged atcf99cd88. Lead verifies
exact6210 evidence entries, local22/inherited59, realHTTP22 each profile, existing
22/17/1/23 regressions and two independent pipeline/escaped-JSON controls. Full
243/243,5/5,outer0;17339 tracked files unchanged. Cross-attempt100 executions,
131 workspace IDs/97 cgroups absent,34 local groups gone, active parents empty,
shared5 unchanged. Deliberate owner-kill gzip streams retain five complete rows
without closing footers; source/evidence limits are explicit. No Mo routing claim.

Two additional source reviews confirm the duplicate-key decoder limitation and
existing non-atomic Fs/HTTP allocation limits. The next Mo brief uses raw member
counts plus integer lexical checks after grammar decode; compiled proof is owed.
Both reviewer panes are closed. Worker implementation remains Astra/low and
separate; no nested delegation or full compiler/machine concurrency.

## Next

The released [[mo-application-workspace-v1|Mo application profile]] connects the
recorded loop to accepted remote tools. Scripted Logstat repair follows separately.
No live-provider, language-value or application-repair acceptance.

## Related

- [[roadmap]]
- [[mo-first-coding-harness]]
- [[decision-log]]
