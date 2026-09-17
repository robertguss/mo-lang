---
title: "Empirical validation plan: how Mo gets judged"
created: 2026-09-13
updated: 2026-09-13
type: concept
tags: [research, agents, verification, roadmap]
sources: [raw/research-runs/empirical-validation-agent-language.pplx.md, raw/research-runs/mo-parallel-tracks-brief-1-empirical.pplx.md, raw/research-runs/agent-authoring-research-frontier.pplx.md, plans/control-run-4.md]
confidence: medium
---

# Empirical validation plan: how Mo gets judged

Fable's reading of the session 6 deep run on empirical validation, held against what the control runs have measured so far. The run's seven pre-registered experiments are a research programme for a lab; this page says which of them Mo can run with what it has, what the control runs already are, and what they are missing to count as evidence.

## Where Mo starts

A new language starts in the no-resource tier: on the one benchmark that translated standard tasks into languages with no training data, models passed 9 percent on average and 0 to 1 percent on hard tasks, against 79 percent for Python, and on Gleam nine in ten generations did not even compile.^[raw/research-runs/empirical-validation-agent-language.pplx.md] Documentation in the prompt moved the odds by 1.2 to 11 times, the largest lever a language designer controls. This is Mo's position today, and the control runs confirm it in miniature: every round's Mo loops are the model guessing at syntax it has never seen.

## What the control runs are, and are not

The control run is the run's Experiment 1, the null hypothesis, at the smallest possible scale: one task, one model, three languages, four rounds. It has already produced the two numbers that matter, that Mo takes about 1.75 times Go's wall-clock and that Mo's checks caught a real bug in one round out of four. It fails every threat-to-validity test the run lists: one task, so no power; the same model each time, so contamination across rounds (the spec is read for the fourth time); Fable grades its own experiment; nothing is pre-registered; tokens are not counted; and the Go and Python baselines carry no bolted-on checks beyond vet and mypy. The run's reference precedent for what happens to unreplicated language claims is the 2019 reanalysis that found the practical effect of language on defects "exceedingly small" once an outside group redid the work.^[raw/research-runs/empirical-validation-agent-language.pplx.md]

## What Mo can run now, in order of cost

| experiment | what it needs | Mo today |
|---|---|---|
| E7, feature ablation | six flags, a task set, a fixed loop | all six factors exist as flags or modes (`--json`, edit by id, capabilities, incremental build, `--sim`, `--no-contracts`); the cheapest and the most Mo-specific |
| E2, cold-start ladder | grammar-constrained decoding, a skill file, retrieval, compiler loops | `PRELUDE.md` and the catalog are the skill file; the grammar exists; retries are the loop; runnable on the corpus's own tasks |
| E6, token accounting | a token ledger per run | not recorded; add to round 5 at zero cost |
| E1, null hypothesis | 833 tasks, 3 models, 5 language conditions with real bolted-on checks | round 5 can take two tasks (logstat, kv), a second model, and a Go baseline with `staticcheck` and a contracts library |
| E4, spec-altitude review | mutants, reviewers, blinding | the founding premise's own test; step 19's mutation test is its seed; needs people |
| E5, real-bug replay | 500 CVEs transpiled | feasible at 50 with a worker, after program 1 |
| E3, maintainability | 32 developers, six months | not before a public Mo |

## What changes because of this page

- Round 5 is pre-registered: thresholds written on its plan page before it runs, following the run's committed shape (success at least 5 points higher, defects at least 15 percent lower, iterations no more than 15 percent higher, all three or it is "mixed").
- Every round records tokens per attempt and separates the amortized preamble from the marginal task cost, as the run's Experiment 6 does.
- Every round records loops to green by cause (a law, a grammar form, a diagnostic, a test mistake, a real bug) and whether the worker wrote Mo directly or wrote a generator for it, since the LLM-facing literature found strong models routing around low-resource languages ([[language-design-for-llms-evidence]]); rounds 2 to 4 wrote Mo directly (Fable, 13 Sep night, [[research-agenda-2026-09-response]]).
- The baselines get their bolted-on checks: Go with `staticcheck` and a contracts library, Python with `pydantic` and `returns`; otherwise the comparison is Mo against nothing.
- The feature ablation is the first experiment worth a worker: six flags, the corpus's programs, three models, one week.
- Spec-altitude review, the premise itself, is the experiment that needs people, and it waits for a public Mo.

## Related

- [[hermes-research-monitoring]] — Ongoing independent evidence monitoring; not an experiment run.
- [[control-run-4]]
- [[case-against-new-languages]]
- [[research-summary-2026-09]]
- [[language-design-for-llms-evidence]]
- [[prompts-mo-parallel-tracks]]
