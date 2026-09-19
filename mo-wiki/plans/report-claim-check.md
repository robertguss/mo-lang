---
title:
  "Report claim check: TypeSafe triage of worker claims against raw evidence"
created: 2026-09-18
updated: 2026-09-19
type: plan
tags: [verification, tooling, agents]
sources: [plans/mo-first-coding-harness.md]
status: in-progress
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

- **For Robert:** Robert has an account and key (18 Sep 2026). Still open: whether raw
  logs may be sent to an external service. The repo's evidence is already
  public, but this is still an outward send.
- The pinned model version (`jev-latest` moves; pin `jev-1.x` for calibration),
  the budget, and the tool's path.
- Where calibration results are recorded, and who reads them.

## Approved, and the calibration brief (19 Sep 2026, 1:59 PM ET)

Robert approved sending worker reports and log excerpts to TypeSafe and has a
key (19 Sep 2026). The readiness items are settled by the lead: the tool lives
at `tools/claim-check/` (a `uv init` project, everything in its virtual
environment); the key is read from the environment variable
`TYPESAFE_API_KEY`, or from `~/.mo-lead/typesafe.env` (mode 0600, outside the
repo), and is never printed, logged or committed; the model is pinned to the
newest `jev-1.x` the Models page lists, by exact name; the budget is at most
2,000 requests for the whole calibration; results are recorded in
`tools/claim-check/calibration/RESULTS.md` and read by the lead. This step is
the **calibration only**. Nothing in the lead's acceptance loop depends on the
tool until its numbers exist and a decision-log row says so.

**Worker:** a fresh Claude Opus session, bypass permissions, own worktree and
Herdr tab. **Write scope:** `tools/claim-check/**` only. No `toolchain/`,
`examples/`, wiki, `audit/`, `HANDOFF.md`; no push. Never use `tr`; `ls` is
aliased, use `/bin/ls`. Load the `typesafe-ai` skill and read the live docs it
names (the citation-check cookbook, Choice, Noul, Confidence, the Python SDK,
Jev 1.13's known limits) before designing a question.

**Never sent:** anything under `audit/mo-audit-*`, any sealed or hidden suite,
any file that matches a secret pattern (tokens, keys, `~/.mo-lead`, private
capability files), anything outside this repository. The sender refuses by
path and by pattern, with a test. Every request's state is also written to a
local, git-ignored `sent/` folder so what left the machine can be audited.

**Parts.**
1. The Shape above, as code: collect claims from the fixed parts of a report;
   check exact facts in code (SHA on the branch, summary line found word for
   word, exit code, each number present); only the residue goes to Jev with the
   four questions of the table, the claim, the report's words and the log
   excerpt as named JSON fields; the gate. The model client sits behind one
   small interface with a recorded-answer fake, so every test runs offline.
   Keep excerpts short: Jev's accuracy falls as unrelated state grows, and it
   does not count or do arithmetic, so every count and comparison is code's.
2. The labelled set, from this repository's history, each case a report, its
   raw log and the known truth: step 36's report and its two hidden defects;
   step 39's corpus test that tested nothing and its fuzz count; the overnight
   review's tests that cannot fail (E3, M1, P1) in
   `audit/evidence/2026-09-19/fable-overnight-review/`; harness step 2's report
   against the live regression the lead found; and as true reports, steps 40
   and 43 and the raw-memory fix (`toolchain/STEP-*-REPORT.md` with the lead's
   logs under `audit/evidence/2026-09-19/fable-lead-verification/`). Plus the
   five planted negative controls listed under Calibration. Say in the results
   how many cases there are; do not pad them.
3. The live run, once the key exists: the numbers named under Calibration
   (planted failures caught, true claims flagged, claims sent to the lead,
   latency, requests and cost as the API reports usage), a threshold chosen
   from them, and the cases it got wrong, each with the exact state, question
   and answer. If the key is absent, finish parts 1 and 2, say so in the
   report, and stop: do not ask for it in any other way.

**Done when.** `uv run pytest` green offline with its summary line and exit
code; `uv run ruff check` and `uv run mypy` clean; the live results recorded or
their absence stated. **Write your final report to
`tools/claim-check/REPORT.md` and commit it last, with a clean worktree.** Small
commits as yourself with a `Co-Authored-By` line naming your model. While
anything runs, wait in the foreground.

## Related

- [[mo-first-coding-harness]]
- [[agent-native-research-synthesis]]
- [[decision-log]]
- [[roadmap]]
