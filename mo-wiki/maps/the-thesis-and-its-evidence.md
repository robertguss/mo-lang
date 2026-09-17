---
title: "The thesis and its evidence"
created: 2026-09-16
updated: 2026-09-16
type: map
tags: [thesis, research]
sources: [index.md, plans/roadmap.md, decisions/decision-log.md]
status: living
---

# The thesis and its evidence

A map of content: the claim, the layers it stands on, and the page where each claim met a measurement. Start with [[state-of-the-project]] for the whole picture; this map is the trail behind it.

## The claim, and how it was restated

- [[01-premise]] — chapter 1: the world Mo is for, the three layers, what is measured, the null hypothesis and the language layer's own null hypothesis
- [[08-milestone]] — chapter 8: the interpreter milestone, every open bet and what first tests it, the control run's measure as restated on 14 Sep
- [[outside-review-2026-09-14]] and [[outside-review-2026-09-14-response]] — the review that led to the restatement, and the reply that named the BEAM null hypothesis and the one-sentence thesis
- [[outside-review-2026-09-13]], [[outside-review-2026-09-13-evidence]], [[outside-review-2026-09-13-response]] — the first outside review and its no-compat fixes (step 18)
- [[research-agenda-2026-09-response]] — seventeen "contradicts Mo" ideas from the research pages, each with a call: agree, disagree, or test
- [[fork-in-the-road]] and [[two-altitudes]] — the earliest statements of what Mo is betting on
- [[d43-five-measurements]] — the five measurements of the parts the rounds do not reach, and the risk against the thesis, named

## Layer 1, the runtime and the process model carry reliability

- [[03-semantics]] — chapter 3: processes, the failure model, restart, timeouts, the runtime surface
- [[d14-processes-are-the-only-identity]], [[d17-mandatory-deadlines]], [[d18-two-kinds-of-failure]], [[d33-bounded-mailboxes]], [[d08-beam-qualities-without-the-beam]]
- Evidence: [[control-run-7]] and [[control-run-8]] (0 defects under a hidden suite, then the outage), [[control-run-10]] (the BEAM's P6), [[interpreter-step-29]] and [[interpreter-step-29b]] (the runtime made honest), [[interpreter-step-31]] (the deferred reply), [[erosion-round]] (the full disk)

## Layer 2, capabilities and recipes carry zero dependencies

- [[06-packages]] — chapter 6: bricks, kits, recipes, the registry
- [[d15-effects-via-capabilities]], [[d30-supply-chain-security]], [[d34-packages-are-recipes]], [[d35-mo-is-an-ecosystem]], [[effects-and-capabilities]]
- [[q17-package-management-and-supply-chain]] — the open question
- Evidence: the dependency column of every round from [[control-run-6]] on (Mo 0 and 0); the store recipe in [[program-4]] and [[program-1]]; the bricks page is still to be written

## Layer 3, the language as the surface

- [[02-laws]], [[04-syntax]], [[05-verification]] — the laws, the surface, the three tiers and the `verified:` line
- [[d02-spec-altitude]], [[d03-source-carries-its-evidence]], [[d04-style-rules-become-laws]], [[d19-negative-space-is-the-contract]], [[negative-space-programming]]
- [[10-language-after-the-rounds]] — chapter 10: what the rounds' evidence says the language should change
- Evidence: [[bodies-as-cache]] (twelve of twelve regenerations at 1.0), [[sampling-as-verification]], the loop columns of [[control-run-6]] to [[control-run-9]] (the laws have not caught a change-induced bug in any language)

## The null hypotheses

- The BEAM: [[d42-elixir-round]], [[control-run-10]], the P6 rows in [[control-run-10]] and [[erosion-round]]
- A familiar language with the checks bolted on: [[control-run-6]] (the Go and Python baselines with vet, staticcheck, mypy, ruff, contracts), and the unfamiliarity-tax experiment named in [[d43-five-measurements]]
