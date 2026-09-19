---
title: "Harness: the Mo agent end to end on the machine, and the scripted Logstat repair"
created: 2026-09-19
updated: 2026-09-19
type: plan
tags: [agents, tooling, verification]
sources: [plans/mo-first-coding-harness.md, plans/mo-application-workspace-v1.md]
status: done
---

# End to end on the machine, and the scripted Logstat repair

## Orientation

Every half of the harness passes its own tests; nothing has run whole. The Mo
agent's application mode ([[mo-application-workspace-v1]]) is tested against a
bridge double and the real Bridge front end over a test owner; the workspace
service and executor pass their live suites on `mo-executor-r01`. This slice
joins them: **the Mo agent, a scripted loopback model, the real workspace
service, real containers on the machine, and the protected verdict**, first on
a trivial task, then repairing one known fault in Logstat. It proves plumbing,
not model ability or language value. No live provider.

The preparation design is Astra's and is sound:
`audit/evidence/2026-09-19/logstat-readiness/design.md` and
`source-review-01.md`; read both. Where this brief differs, this brief wins.
Hermes's research ([[hermes-daily-2026-09-19]]) sets the reporting shape:
admission, execution, reply (produced versus received) and cleanup are four
separate observations, never one success count.

Worker: a fresh Claude Opus session, bypass permissions, own worktree and Herdr
tab. The lead owns wiki, audit, acceptance.

## Write scope

New `examples/programs/agent/tests/end-to-end-v1/` (drivers, scripted model,
fixtures' preparation, README, small evidence) and, only if a defect there
blocks the run, the minimal fix in `examples/programs/agent/*.mo` or
`toolchain/harness/executor/**`, each with a failing control first and named in
the report. No compiler or runtime source. No `.mo` files under any evidence
folder (the corpus runs every `.mo` it finds); prepared fixture trees live
outside `examples/` or under an ignored cache. Nothing under `mo-wiki/`,
`audit/`, `HANDOFF.md`. No push. Never use `tr`; `ls` is aliased, use `/bin/ls`.

**The machine is yours for this slice**, exclusively: `mo-executor-r01`, its
Docker and the two slices, through the accepted code paths only
(`Workspace`, `workspace_http`, `application` policies). No image, `/opt`,
resource or configuration changes. Every run under
`toolchain/harness/executor/guarded.py` (it kills the group); finish every
session with `toolchain/harness/executor/inventory.py` proving nothing is left.
Do not run the toolchain's full `zig build test`.

## Parts

1. **The driver.** One command that: prepares a candidate tree; starts the real
   workspace service for it with the application policy (as
   `workspace_http/live.py --application` does); writes the private bridge
   configuration (0600, outside the Book and the candidate); starts a scripted
   loopback model; runs the Mo agent's `application-workspace` CLI against both,
   in `mo run` and as a `mo build` binary; then freezes, runs the protected
   verifier, collects and disposes. It records the four observations per tool
   call, from the service's journal and the agent's Book independently.
2. **Smoke.** A trivial tree and a script that calls each of the six tools once
   and answers. Checks: every tool result in the Book matches what the service
   journalled; the Book prefix is on disk before each dispatch; the capability
   token appears nowhere in the Book, the report, argv, or any log; operator
   and candidate canaries prove no local fallback.
3. **Logstat repair**, per the readiness design: the fault `top: 5` to `top: 1`
   at `logstat/main.mo`, clean, faulty and repaired behaviour each proved by the
   protected verifier (four CLI goldens, eight Main tests) before the agent run
   is trusted; the scripted nine steps (model, failing command, model, read,
   model, exact edit, model, passing command, answer); protected verification
   on the frozen snapshot afterwards; a forged-success control and a
   wrong-candidate control must both be refused by the verdict.
4. **Negative runs.** The service killed mid-command; a command past its
   candidate limit; the agent's outer deadline reached: each must end with a
   truthful report (execution unknown where it is unknown) and a clean
   inventory.
5. **What breaks.** This is the first whole run; expect defects at the joins.
   For each: a failing control first, the smallest fix, named in the report
   with its file and line. Known suspects from the lead's review
   (`audit/evidence/2026-09-19/fable-overnight-review/README.md`): H1 (any file
   operation slower than 2 s ends the run), H4 (valid output past 64 KiB
   reported as `output_encoding`), H5, H6. Do not fix what the run does not hit;
   list what you saw.

## Numbers and done when

Both runtimes. Wall time per run and per tool call, measured. Real exit codes
and summary lines. Evidence under 2 MiB. Small commits as yourself with a
`Co-Authored-By` line naming your model. **Write your final report to
`examples/programs/agent/tests/end-to-end-v1/REPORT.md` and commit it**:
commits, the exact commands to rerun each part, defects found at the joins,
decisions the brief did not cover, limitations. While anything runs, wait in
the foreground so your tab does not look finished.

## Result

Accepted 2:20 PM ET, 19 Sep 2026, merged to `main` through `lead/verify-e2e`
(`5403d370`). Worker: Claude Opus 5; report
`examples/programs/agent/tests/end-to-end-v1/REPORT.md`. For the first time the
Mo agent ran end to end on the machine, in `mo run` and as a binary: all six
tools through the real service and real containers, each Book result equal to
the journalled reply, the scripted Logstat repair RED then GREEN, the protected
verdict passing it and refusing a forged success and a candidate that rewrote
its own test, three negative runs with truthful reports, every workspace proved
gone. Lead rerun on the machine (`evidence/lead-*`): smoke in both runtimes, the
native Logstat repair with both controls, service-killed and candidate-limit,
all exit 0 with no failed check; inventory `{"runs": 74, "workspaces": 56,
"cgroups": 71, "clean": true}`; a lead scan of 175 evidence files for the seven
run tokens found none. No full suite was run for this slice: it adds no `.mo`
and no toolchain file, and the suite was 263 of 263 on both platforms on the
tree beneath it. Two defects found and not fixed, by the brief: D1 (the clamped
command's margin) joins [[mo-agent-report-cap]]; D2 (after a client disconnect
the operator cannot freeze or verify, so a run that ends on a timed-out call
loses its verdict) is a required control of the Mo six-tool server. The model
was scripted: this proves the plumbing, not model ability or language value.

## Related

- [[mo-application-workspace-v1]]
- [[mo-first-coding-harness]]
- [[mo-harness-in-mo]]
- [[hermes-daily-2026-09-19]]
