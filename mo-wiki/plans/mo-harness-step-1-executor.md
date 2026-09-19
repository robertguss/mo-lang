---
title: "Harness step 1: the two high executor defects, and the duplicate machinery deleted"
created: 2026-09-19
updated: 2026-09-19
type: plan
tags: [agents, tooling, security]
sources: [plans/mo-harness-in-mo.md]
status: in-progress
---

# Harness step 1: executor defects and deletion

## Orientation

Step 1 of [[mo-harness-in-mo]]. The findings are in
`audit/evidence/2026-09-19/fable-overnight-review/README.md` (E1, E2, E4, E5,
E6). The Python under `toolchain/harness/executor/` is being cut down before
most of it moves to Mo, so fix only what stays or what the machine runs on, and
delete what is duplicate. Worker: a fresh Claude Opus session, bypass
permissions, own worktree. The lead owns the wiki, audit and acceptance.

## Write scope

`toolchain/harness/executor/**` and `toolchain/harness/provider/**/*.py` only.
No Mo source, no compiler, no `mo-wiki/`, `audit/`, `HANDOFF.md`. Do not delete
or edit any existing `evidence/`, `attempts/` or `sources/` directory: they are
history. No machine (`mo-executor-r01`), Docker or `/opt` changes; the machine
run is the lead's. No push. Never use `tr`.

## Parts

1. **E1.** A `docker rm -f` that times out must not power off the machine.
   Distinguish a cleanup timeout (report cleanup unconfirmed, leave evidence,
   retry within a stated bound) from a proven containment failure (the only
   case that may power off). Failing test first.
2. **E2.** A refusal before `claim()` returns its structured refusal; no
   `FileNotFoundError`. The failing test issues the refusal as the *first*
   call to a fresh workspace.
3. **E4, E6.** A truncated or undecodable `state.json` is quarantine, never
   `refusal/completed`. `files.Refusal` stops subclassing `ValueError`, or the
   catch narrows, so programming errors surface. State writes `fsync` before
   rename. Failing tests first.
4. **E5.** The machine side validates `name` against
   `^mo-executor-[0-9a-f]{32}$` before it reaches systemd. Failing test first.
5. **Delete duplicates.** The six guarded-runner copies
   (`recovery/run_guarded.py`, `application/run_attempt.py`,
   `workspace_http/run_guarded.py`, `provider/run.py`, `provider/auth/run.py`,
   `provider/bridge/run.py` and `execute.py`) become one helper of about 60
   lines that records the child's real return code. The per-run probe and
   inventory scripts (`red_lifetime.py`, `review_baseline.py`,
   `ipc_deadline_probe.py`, `controller_deadline.py`, `live_frontend.py`,
   `frontend_control.py`, `live_owner.py`, `observe_regression.py`,
   `diagnose_runtime.py`, `inspect_machine.py`, `distribution_diff.py`,
   `final_inventory.py`, `final_receipt.py`, `smoke.py`) become one
   `inventory.py`, or go if nothing calls them. The four copies of the
   exec-bootstrap string become one. Check every caller before deleting; say
   what each deleted file was for in the commit message.

Do not restructure the live suites (`live.py`, `local.py`,
`test_workspace_live.py`, `selftest.py`, `controls.py`): that is step 2 and
another worker's. Keep them importable and passing.

## Numbers and done when

All local Python tests pass (84 before; report the new count) under
`toolchain/bench/step36/guard.py`, with the real summary line and exit code.
Report non-blank non-comment Python lines before and after, per directory,
with the counting command. Small commits as yourself with a `Co-Authored-By`
line naming your model. Final report to the lead: commits, decisions the brief
did not cover, anything you chose not to delete and why, what the lead must
re-run on the machine.

## Related

- [[mo-harness-in-mo]]
