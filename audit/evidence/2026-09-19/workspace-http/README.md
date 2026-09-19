# Workspace HTTP lead evidence

GPT-6-Astra lead, 19 Sep 2026, 6:38 AM ET. Independently accepted after the
integrated full suite and final cross-attempt closure. Read this interpretation
after forming your own reading of the raw evidence.

## Exact source and integration

Worker branch `harness/workspace-http-v1`, exact base
`3023a01a744d1580ca9814e595ddf990a12e456d`, final tip
`42015b73cce5f4f97d4479413354780c94b13e6c`. Product freeze is
`1cf268b356a63665214ca8331bfc55828b643603`; later commits change evidence only.
All six worker commits have actual GPT-6-Astra author and committer identities.
The final integrated source/evidence checkpoint is
`cf99cd88e186cf293a4112582fe2d26a0f7b69ff`.

`integration-01/` retains five immutable cherry-picks; `integration-02/` retains
the final evidence-only transfer. Exact executor trees match. All6211 worker
paths are new under `toolchain/harness/executor/workspace_http/`; core bodies,
provider, compiler and Mo sources are unchanged. `worker-evidence-proof.json`
in each final lead attempt verifies the exact6210 manifest entries, every byte
count/SHA256, production/contract freeze and seven unchanged core files. The
earlier local attempt verified4634 entries before final evidence arrived; its
product bytes are identical. Worker report/evidence remain in the owned tree.

## Independent checks

| raw attempt | result |
|---|---|
| local-01, launch-local-01 | HTTP22, inherited59; unknown/empty/duplicate selections reject with exit2 for both runners before output creation |
| busybox-01, launch-busybox-01 | actual BusyBox HTTP22/22 and two real review controls; source unchanged and positive inventory |
| application-01, launch-application-01 | actual application-selection HTTP22/22; the supplementary review runner again uses BusyBox, two controls |
| regression-01, launch-regression-01 | existing workspace22, executor17, collector-loss1, application23; sequential raw transport capture |
| extra-01, launch-extra-01 | two new real controls below, both pass |
| full-01, launch-full-01 | build0; tests243/243,5/5; outer0,409.32s; all groups absent |

Every finished lead attempt retains actual child/outer exits, selected counts,
process groups, source SHA baselines, unchanged-source assertions and raw output.
Final attempts each check17339 tracked toolchain/examples files; local checks
15763 before final worker evidence integration. All are byte-identical afterward.
No machine workloads run during the full compiler suite. All attempts remain
below16MiB including their launch output. Capability files are privately retained
and Git-ignored; final closeout scans retained bytes for their exact values.

`closeout-01/` rechecks100 execution resources,131 recorded workspace IDs
(including external HTTP identities) and97 actual candidate cgroups: all absent.
Both active parents are empty; images/manifest/limits and shared5 remain exact.
All34 lead acceptance/inventory groups are absent. Its2696-entry manifest hashes
retained nonsecret evidence. All48 excluded capability values are absent from
the retained bytes, including decoded gzip contents. Largest attempt10,819,838
bytes, below16MiB. Lead runpane is shell-idle after closure.

The post-dispatch pipeline control first proves the command registered, then
sends a second valid write request on the same connection. The wire reports
unknown and closes admission; the owner records one completed successful command,
one claim, and confirmed cleanup. Its actual script proves the second marker was
never created. This does not turn uncertain delivery into successful delivery.

The escaped-size control writes36000 UTF-8 bytes whose JSON string is72002 bytes.
Reading returns completed `result_too_large`, preserving the existing controller
cap. A later small read succeeds with admission open; all three claims and normal
cleanup are retained. No policy or quota changed.

## Corrections and limits

Immutable reviews: `contract-review-01.md`, `lead-owner-review-75680f31.md`,
`source-review-75680f31.md`, `lead-correction-review-83a72dd4.md`,
`lead-ipc-review-1cf268b3.md`. Exact review snapshots are recorded in
`source-review-01.json` through `source-review-03.json`.

`drain-red-03/` and `drain-green-01/` use identical probe bytes: both actual
post-response drain failures on75680 become green on83a72. Earlier setup failure
and partially observed red are retained. `ipc-deadline-red-01/` returns200/success
at2.413s for a2s file wait on83a72; the identical probe returns504/unknown at2.00343s
on1cf. No source bytes changed during these runs. Their guarded wrappers retain
actual exits and positive group absence. Worker independently reproduced both.

Worker application cleanup originally exceeded the controller's strict deadline
ceiling. Delete<=55s plus core transport allowance now shares60s cleanup time.
Actual numeric-controller controls distinguish60.05 rejected and55 accepted
before an expected missing-workspace refusal; no clock-skew cause is claimed.
Worker pre-correction full243/243 is labelled historical; lead full-01 covers1cf.

`gzip-review-01.json` retains a failed strict evidence-inspection attempt: actual
owner SIGKILL leaves the BusyBox/application owner-death gzip streams without a
final footer. Each decodes to five complete JSON rows; original bytes remain.
There is no claim about an unreturned in-flight transport. Other streams have
complete gzip framing. This is distinct from the older unexplained recovery
snapshot incident, whose lost raw response remains unavailable.

Scope is the Python one-run loopback interface and actual isolated Workspace.
No Mo application routing, live provider,900s soak, crash durability, unconditional
synchronous cleanup bound across inherited locks, or proof of client receipt.
Lease is admission; persistent owner cleanup outlives request/response failures.
Unknown command outcomes remain unknown even when later cleanup is confirmed.

## Reproduce without overwriting evidence

From the repository root at the integrated source, use an owned Herdr run pane.
`launch.py` supplies numeric child/outer guards and positive group cleanup:

```text
python3 -B audit/evidence/2026-09-19/workspace-http/launch.py local new-local-rerun 42015b73cce5f4f97d4479413354780c94b13e6c
```

Use a fresh lowercase name, and substitute mode `busybox`, `application`,
`regression`, `extra` or `full` with a distinct fresh output name. Real modes need
exclusive access to the unchanged dedicated machine; full runs separately.
`closeout.py` aggregates the six named accepted lead attempts, rechecks their
recorded resource identities, pins/limits/shared containers and local groups,
and hashes retained nonsecret bytes. Its output directory must also be fresh.
The scripts are lead-owned audit instruments; they do not edit product sources.
