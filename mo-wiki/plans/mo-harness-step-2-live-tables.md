---
title: "Harness step 2: live suites as case tables, tests that can fail"
created: 2026-09-19
updated: 2026-09-19
type: plan
tags: [agents, tooling, verification]
sources: [plans/mo-harness-in-mo.md]
status: in-progress
---

# Harness step 2: live suites as tables

## Orientation

Step 2 of [[mo-harness-in-mo]], after [[mo-harness-step-1-executor]]. The
Python under `toolchain/harness/` is being cut to what its role needs before
most of it moves to Mo. Six hand-written case lists become one runner and case
tables; tests that cannot fail are replaced by ones that can. Review findings:
`audit/evidence/2026-09-19/fable-overnight-review/README.md` (E3, and the Tests
notes under Workspace HTTP). Worker: a fresh Claude Opus session, bypass
permissions, own worktree and Herdr tab. The lead owns wiki, audit, acceptance.

## Write scope

`toolchain/harness/executor/**` and `toolchain/harness/provider/**` (any file
type, so the stale READMEs can be fixed). Not `evidence/`, `attempts/` or
`sources/` directories: history. No Mo source, compiler, `mo-wiki/`, `audit/`,
`HANDOFF.md`. **You may not run anything against the machine `mo-executor-r01`,
Docker or `/opt`**: another worker may be using the host, and the live reruns
are the lead's. No push. Never use `tr`.

## Parts

1. **One live runner, case tables.** `recovery/live.py`, `workspace_http/live.py`,
   `workspace_http/local.py`, `test_workspace_live.py`, `selftest.py` and
   `application/controls.py` keep every case they have today, by name, with the
   same command lines and the same printed summary shapes (the lead's reruns and
   records quote them: `{"count": 17, "passed": 17, ...}`, `{"controls": 22,
   ...}`, `{"groups": 22, ...}`, `{"controls": 23, ...}`). Shared setup, run,
   cleanup and reporting move into one module; each suite becomes a table of
   cases plus the few functions that are really its own. Step 1 changed two
   injection strings in `recovery/live.py`; keep them.
2. **E3.** `test_foreign_state_retained`,
   `test_missing_root_is_not_runtime_absence`,
   `test_dispatched_missing_storage_requires_proof` and
   `test_conflicting_local_manifest_refused_before_transport` assert the
   pre-seeded default. Rewrite each so it fails when `recover()`'s body is
   broken (show it: replace `read_json` with a function that raises, keep the
   output). Do not rewrite `recover()` itself; that moves to Mo in step 5.
3. **The HTTP test double.** `WorkspaceDouble.call` ignores `args`. Give the
   local suite real coverage of path containment, `exact_edit` matching
   (missing, multiple, empty) and truncation, without the machine, and stop
   tests mutating production globals where a parameter will do.
4. **Stale references.** `provider/README.md`, `provider/auth/README.md`,
   `provider/bridge/README.md` and `provider/auth/attempt.sh` name runners step 1
   deleted; point them at `executor/guarded.py`. `recovery/readiness_probes.py`
   fails to import: fix or delete it, saying which and why.

## Numbers and done when

All local suites pass under `toolchain/bench/step36/guard.py` with real summary
lines and exit codes (before: executor 96, application 25, `local.py` 22).
Counted Python lines (non-blank, non-comment) before and after, per directory,
tests and other code separately, with the command. A list of every live case
name before and after, proving none was lost. Small commits as yourself with a
`Co-Authored-By` line naming your model. **Write your final report to
`toolchain/harness/executor/STEP-2-REPORT.md` and commit it**: commits,
decisions the brief did not cover, what the lead must rerun on the machine.

## Related

- [[mo-harness-in-mo]]
- [[mo-harness-step-1-executor]]
