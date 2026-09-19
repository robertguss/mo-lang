---
title: "The agent's report cap: from a defect's margin to the profile's own bound"
created: 2026-09-19
updated: 2026-09-19
type: plan
tags: [agents, runtime, verification]
sources: [plans/toolchain-raw-memory-report.md, plans/mo-application-workspace-v1.md]
status: briefed
---

# The agent's report cap

## Orientation

`report_cap()` in `examples/programs/agent/application.mo` is 262,144 bytes
because a toolchain defect corrupted larger reports. That defect is fixed in
both runtimes ([[toolchain-raw-memory-report]], accepted 19 Sep 2026), so the
number now describes nothing. The lead's decision: a report stays bounded, but
by what the profile can legitimately produce, so the cap is a defence that a
correct run never meets. Worker: a fresh Claude Opus session, bypass
permissions, own worktree and Herdr tab, based on the `main` that holds the
end-to-end slice. Small: one sitting.

## Write scope

`examples/programs/agent/application.mo`, its tests and sidecars,
`examples/programs/agent/tests/application-workspace-v1/` (matrix, README
items 10 and the 256 KiB sentence, new evidence under 2 MiB). No toolchain, no
wiki, no `audit/`, no `HANDOFF.md`, no machine, no push. Never use `tr`; `ls`
is aliased, use `/bin/ls`.

## Parts

1. **RED first.** A matrix row with a transcript between 256 KiB and the new
   bound that must render whole and byte-identical in both runtimes (it fails
   today with `transcript_too_large`); sizes 300,000, 1,000,000 and the largest
   the profile allows. Commit the failing output.
2. **The bound.** Derive `report_cap()` from the profile's own limits (steps
   times the request and response bounds, plus the model text bound), as an
   expression of the existing functions, not a new literal. The `bounds` line of
   the profile reports the derived value; update `matrix.py`'s expectation.
   Rewrite the comment: no mention of the defect as a reason.
3. **Still refused.** One row past the bound still gives the proved
   `transcript_too_large` error with `persistence: proved`.
4. **Whole-report check.** For the largest size, diff the entire report between
   `mo run` and the `mo build` binary (the raw-memory worker compared only the
   last line).

## Numbers

Wall time and peak resident memory of the largest report, both runtimes, best
of five, load average beside them.

## Done when

Every process under `toolchain/bench/step36/guard.py`. The focused matrix and
the agent's `mo test` green in both runtimes with real summary lines and exit
codes; **the full suite and the machine are the lead's**. **Write your final
report to `examples/programs/agent/tests/application-workspace-v1/REPORT-CAP.md`
and commit it.** While anything runs, wait in the foreground.

## Related

- [[toolchain-raw-memory-report]]
- [[mo-application-workspace-v1]]
- [[mo-harness-in-mo]]
