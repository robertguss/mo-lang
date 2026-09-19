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

## Next

[[mo-workspace-http-v1]] will expose six tools with cleanup ownership surviving
request lifetime. A separate Mo application profile and then scripted Logstat
repair follow. No live-provider, language-value or application-repair acceptance.

## Related

- [[roadmap]]
- [[mo-first-coding-harness]]
- [[decision-log]]
