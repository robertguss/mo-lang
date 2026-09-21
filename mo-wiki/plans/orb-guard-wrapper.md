---
title: "Orb guard wrapper: retain payload ownership during cancellation"
created: 2026-09-20
updated: 2026-09-20
type: plan
tags: [verification, tooling, security]
sources: [plans/interpreter-step-42.md, plans/mo-executor-foundation.md]
status: complete
---

# Orb guard wrapper

## Result — 20 Sep 2026, evening ET

Accepted at main6b35871e, worker18825853, independently verified tree6a9f5898.
Lead wrapper33/33, unchanged direct6/6,2/2,1/1 pass; old-wrapper overflow fails
0/1 with payload and descendant live and output growing before fallback cleanup.
Oracle reviewed the corrections and final evidence; no blockers remained. Raw
logs/exits are under `audit/evidence/2026-09-20/orb-wrapper/`.

The shared in-process supervisor owns the actual payload. Failed/unknown probes
or cleanup return125 in wrapper and standalone; real child status remains
separate. Missing RSS selection differs from genuine probe failure. Signals
retain one grace deadline even during startup; final output size enforces the
abort threshold. Zombie-only cleanup is not literal group absence.

Limits remain explicit: synchronous Popen is not hard-bounded; direct-child RSS
is not aggregate memory; escaped sessions are not contained;16MiB is a trigger,
not a hard cap. Outer-deadline coverage is clock-injected branch proof. No
Darwin or machine-isolation acceptance follows.

## Orientation

Continuation of [[interpreter-step-42]] for the wrapper used by
[[mo-executor-foundation]].

Oracle confirmed an integration regression after the direct guard started a
dedicated child session. executor/guarded.py starts the guard in one group, then
kills only that group on output overflow, outer timeout or TERM/INT. The payload
is now in another group, can survive, and is absent from the wrapper's cleanup
observation. Direct guard controls remain valid; they do not verify this
wrapper. Lead tests avoid guarded.py until this repair is accepted.

## Write scope

A fresh medium xxlarge worker owns toolchain/harness/executor/guarded.py,
toolchain/bench/step36/guard.py, a new wrapper-specific regression script and
report/raw evidence under toolchain/harness/executor/guard-orb/. It may update
the wrapper's README section only. No compiler, server, adapter, remote,
recovery, provider, shared infrastructure, CI, wiki or audit changes. Existing
Step42 guard controls and raw evidence are immutable. Other workers exclude the
guard. Base is main1839785e; no worker push or nested delegation.

## Parts

1. Make the guard import-safe and reuse its supervision core in-process from
   guarded.py so the receipt owner directly owns the payload and its group. Keep
   both CLIs, attempt files, cwd/home handling and standalone behavior.
2. Preserve startup signal queuing and final group cleanup. Wrapper cancellation
   forwards then escalates within a fixed grace; repeated signals do not reset
   it. Bound RSS inspection, reaping and cleanup probes. No indefinite waits.
3. Record actual payload status separately from wrapper policy result. Overflow
   or outer deadline gives124 only with confirmed cleanup; unknown/failed
   cleanup wins as125. Keep group_absent literal; distinguish zombies from live
   members.
4. Preserve the16MiB abort threshold, including fast exit overflow. It is not a
   hard retained-file cap. Prove output has stopped after cleanup.

## Numbers

Regression cases have finite payload lifetimes and output, synchronized
readiness, independent PID/group observation, a surviving unrelated sentinel,
and bounded finally cleanup that cannot depend on the tested wrapper. Exercise
overflow, responsive/ignoring TERM/INT, startup and repeated cancellation,
hanging RSS probe, natural/nonzero/signal exits, fast overflow/binary output,
probe failure with cleanup125 precedence, and regression-harness failure. Retain
bounded old-wrapper REDs before GREENs. Rerun unchanged direct-guard core,
startup and harness-failure controls. No machine/container or memory benchmark.

## Done when

Return a fixed local commit/bundle, exact scope diff, source design and raw logs
with real exit files. Explain status compatibility and bounded timing honestly.
Lead independently runs controls and requests Oracle review before accepting.
RSS remains direct-child only; descendants escaping the group are outside this
mechanism. This does not establish container isolation or Darwin coverage.
