---
title: "Harness step 8: the Mo agent's review findings"
created: 2026-09-19
updated: 2026-09-19
type: plan
tags: [agents, verification, processes]
sources: [plans/mo-harness-in-mo.md]
status: in-progress
---

# Harness step 8: Mo agent findings

## Orientation

Step 8 of [[mo-harness-in-mo]]. Findings M1 to M8 in
`audit/evidence/2026-09-19/fable-overnight-review/README.md`. The code is the Mo
coding agent under `examples/programs/agent/`; learn Mo from the surrounding
code and `toolchain/PRELUDE.md`. Worker: a fresh Claude Opus session, bypass
permissions, own worktree based on the lead's `main`, which already contains
the rebuilt application workspace. The lead owns the wiki, audit and acceptance.

## Write scope

`examples/programs/agent/*.mo`, `examples/programs/agent/tests/coding-fixture-v1/`
(not its `evidence/`), and the `examples/programs/.mo.ids` records and
`verified:` footers those changes regenerate (use the real `mo test --write`;
never hand-edit a hash). No toolchain source, no `tests/application-workspace-v1/`
except where a changed signature forces a call-site edit, no `mo-wiki/`,
`audit/`, `HANDOFF.md`. No machine, no push, no new syntax. Never use `tr`.
No `.mo` files in any evidence folder: the corpus runs every `.mo` it finds.

## Parts

1. **M1, M2.** `tests/coding-fixture-v1/boundaries.mo`: each mode asserts the
   outcome it exists for, unguarded, and an error arm fails the test unless that
   mode expects that exact error. Remove the assertion the code already
   guarantees. Show each rewritten test failing against a deliberately broken
   copy of the code it covers (a mutant), and keep that output.
2. **M5, M6.** `edit-empty` and `command-failure` join `CASES` in `run.py`; the
   four edit refusals assert their reason.
3. **M4.** A completed response already in hand is reported as completed even
   if the deadline has just passed; the run may still stop. Failing test first.
4. **M3.** `main.mo`'s outer ask has real slack over budget plus grace, or the
   budget is derived from the outer deadline. Failing test first.
5. **M7.** `exact-edit.mo:43` refuses instead of falling back to `""`.
6. **M8.** The flag-gated budget checks in `run.mo` (`profiled`, formerly
   `fixture`) fold into `asks?`/`uses?`/`budget_end` so there is one budget
   rule; resolve the off-by-one at the token bound and say which way and why.
   The 12 legacy CLI goldens, the coding-fixture matrices (22 cases per
   runtime) and the application workspace controls must still pass. If one
   budget rule cannot serve legacy, fixture and application runs, stop and tell
   the lead with the source evidence; do not invent a fourth mode.

## Numbers and done when

Both runtimes (`mo run` and a `mo build` binary), every process under
`toolchain/bench/step36/guard.py`. You may run `zig build` and focused tests
with `-Dtest-filter`; the full `zig build test` is the lead's. Report real
summary lines and exit codes, Mo source lines before and after per file, the
mutant outputs for part 1, decisions the brief did not cover. Evidence under
1 MiB. Small commits as yourself with a `Co-Authored-By` line naming your model.

## Related

- [[mo-harness-in-mo]]
- [[mo-coding-fixture-v1]]
