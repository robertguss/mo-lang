---
title:
  "Report claim check: TypeSafe triage of worker claims against raw evidence"
created: 2026-09-18
updated: 2026-09-18
type: plan
tags: [verification, tooling, agents]
sources: [plans/mo-first-coding-harness.md]
status: proposed
---

# Report claim check: TypeSafe triage of worker claims against raw evidence

## Orientation

Robert chose this on 18 Sep 2026, 11:00 PM ET, from three possible places to use
TypeSafe in the project. It is a **proposal only**. The implementation pause
still holds: nothing is built, installed or called until Robert approves a
bounded start and the lead confirms it is ready.

The problem: a worker's "green" is a claim, not a result. In step 36 (17 Sep
2026), two defects sat behind a suite the worker had reported as green. The Step
39 list adds more failures of the same kind: false-success status propagation,
empty selection, and fuzz-batch counting. Today the lead catches these by
reading the logs by hand.

The tool compares each claim in a report with the raw output it rests on, and
gives the lead an ordered list of places to look. **It never accepts anything.**
The lead still runs the suite itself before any acceptance. The checklist in
`mo-lead` is unchanged.

TypeSafe in three lines: you send a state (text or JSON) and typed questions to
its model, Jev. A Choice question picks one option and returns a probability for
each. A Noul question returns the probability that the answer is yes.

## Shape

This is the
[citation-check cookbook](https://docs.typesafe.ai/cookbooks/citation_check.md)
applied to worker reports: plain code first, one judgment per claim, then a gate
on confidence.

1. **Collect the claims (code).** Parse the parts of the report whose format the
   brief already fixes: the numbers table, the `zig build test --summary all`
   line and its exit code, commit SHAs, and the "Decisions the brief did not
   cover" list. The model does not pull claims out of free prose. A report that
   is missing a required part gets flagged as `incomplete` right away.
2. **Check exact facts (code).** Is the SHA on the branch? Does the quoted
   summary line appear word for word in the tee'd log? Does the recorded exit
   code match? Does each number appear in its raw output? A string that cannot
   be found is marked `not found`, and the model is not asked.
3. **Judge the rest (Jev).** Code finds the log section that each surviving
   claim points to. Then one request per claim asks the questions below
   together.
4. **Gate (code).** `contradicted`, `not found` and `incomplete` always go to
   the lead. So do `unsupported` and anything below the confidence threshold.
   `supported` at or above the threshold is listed last, and is still not
   acceptance.

## The questions

| id                | type   | asks                                                                            |
| ----------------- | ------ | ------------------------------------------------------------------------------- |
| `relation`        | Choice | Does this output support the claim, contradict it, or say nothing about it?     |
| `empty_selection` | Noul   | Does the output show zero tests selected, run or counted?                       |
| `masked_failure`  | Noul   | Does the output show a failure, panic or timeout while still ending in success? |
| `skipped`         | Noul   | Does the output show tests skipped, filtered or not reached?                    |

Each question carries the claim, the report's own words and the log excerpt as
named JSON fields, and each gets its own criteria. The three Nouls cover the
known ways a run can look green without being green. Code acts on a Noul only
when its claim depends on it; a Noul near 0.5 means "can't tell", not "half
bad".

## Calibration before any use

Nothing is final until measured. Before the lead relies on the tool:

- **Historical cases with known outcomes:** the step 36 report and its two
  defects, the Step 39 A/B worker outputs, and a set of accepted steps whose
  reports were accurate.
- **Planted negative controls:** a made-up summary line, an exit code that
  contradicts the log, "0 passed" reported as green, a timeout followed by
  success, and a SHA that is not on the branch.
- **Numbers to report:** how many planted failures it catches, how often it
  flags a claim that was true in the accepted steps, how many claims it sends to
  the lead, its latency and its cost. Any threshold comes from these results,
  not from the cookbook's 0.8.

## Boundaries

- **Auditor independence.** The tool never reads `audit/mo-audit-*` files or a
  sealed suite. Its output is the lead's working note. It is never raw evidence,
  never a path in a `ready` record, and never a reading.
- **Harness comparison.** It runs outside the Mo harness and outside Pi, so it
  does not change the matched comparison in [[mo-first-coding-harness]].
- **Where it lives.** It is lead-side Python (`uv init`), outside `toolchain/`
  and `examples/`. The exact path is a readiness item.

## Open before readiness

- **For Robert:** a TypeSafe account and `TYPESAFE_API_KEY`, and whether raw
  logs may be sent to an external service. The repo's evidence is already
  public, but this is still an outward send.
- The pinned model version (`jev-latest` moves; pin `jev-1.x` for calibration),
  the budget, and the tool's path.
- Where calibration results are recorded, and who reads them.

## Related

- [[mo-first-coding-harness]]
- [[agent-native-research-synthesis]]
- [[decision-log]]
- [[roadmap]]
