---
title: "Direction 43: Five measurements only an AI-written world allows"
created: 2026-09-15
updated: 2026-09-17
type: direction
tags: [verification, agents, roadmap, thesis]
sources: [spec/design-v0/01-premise.md, spec/design-v0/08-milestone.md, plans/control-run-7.md, decisions/decision-log.md]
number: 43
status: locked
origin: "Fable, 15 Sep 2026, evening, at Robert's request to drive"
confidence: medium
---

# Direction 43: Five measurements only an AI-written world allows

Robert, 15 Sep 2026, evening: the project is for AI, not humans; Fable should propose what to test and measure, including things opposite the thesis. This page is the first answer. It starts from what a model knows about itself when it writes code: it generates left to right with no global view, so its errors are losses of coherence across distance; it reads expensively, so a language's readability for it is tokens read per correct change; it verifies badly by thought and well by running, so the compiler's answer is its real interface; and it is not one writer but a distribution, so the same spec can be implemented many times cheaply, which no human team could do and which almost no language design uses.

## 1. Bodies are cache (spec completeness)

**Hypothesis.** If the spec altitude is real, bodies are regenerable. **Measure.** Take a finished program, delete every function body, keep signatures, contracts, `never` clauses, intents, and tests; fresh agents regenerate the bodies; run the hidden suite. The fraction of the program that comes back correct is the spec's completeness. **Prediction.** Above 0.8 for the ledger, lower for the agent program. **What it decides.** High: recipes and bricks work by construction and the supply chain is solved by regeneration. Low: the spec altitude is a slogan. **Cost.** Two sessions per program. Robert, 15 Sep 20:40: all six programs, both runs (decision log).

## 2. Sampling as verification

**Hypothesis.** N implementations of one spec disagree exactly where a defect is. **Measure.** Implement one module N times (N = 5) from the same spec; run all N against each other on random inputs; count disagreements; compare with the defects the hidden suite finds in the same module. **Prediction.** Differential disagreement finds at least half of the suite's defects with no suite written. **What it decides.** Whether `mo test` should be able to sample, and whether a hidden suite is even needed for a spec'd module. **Cost.** Tokens only.

## 3. The erosion round

**Hypothesis.** Mo's laws hold a program's quality across generations of fresh maintainers; Go and Python drift. **Measure.** Ten changes in sequence to round 7's job queue, each by a fresh agent that sees only the current program, in all three languages (four from round 10: Elixir joined as the BEAM's row); the hidden suites after every generation; defects and regressions per generation, tokens read per change. **Prediction.** Go and Python each accumulate at least three defects by generation ten; Mo at most one. If wrong, it is the most important result the project could produce. **Cost.** Forty sessions; the maintenance round (round 8) is generation one. Running: five generations by 16 Sep, the reading on [[erosion-round]] (Mo carries one new defect and one carried, Go and Python one carried each, Elixir three).

## 4. The incident round

**Hypothesis.** The runtime's value to an agent is that it can answer "what happened" precisely. **Measure.** A failing production run of a Mo service, given to an agent without the code first: once from logs, once from the event ring and a deterministic replay (directions 38 and 40). Time to the right diagnosis, correctness of the fix. **Prediction.** From the ring and replay, the fix is right first time in most cases; from logs, under half. **What it decides.** Whether directions 38 and 40 are built or dropped. **Cost.** One session per incident; needs program 7 or the ledger under a planted fault.

## 5. Two columns for every round

**Tokens read per correct change** (whether collapsed bodies pay), and **first-fix rate per diagnostic** (for each of Mo's 60 diagnostics, how often the first fix after seeing it is correct; a diagnostic below 0.7 is rewritten). Both come from the panes' token counts and the loop logs already kept. **Cost.** Nearly free; starts with round 8.

## The risk against the thesis, named

The largest tax on Mo is that no model has seen it. Every loop count mixes "the law caught something" with "the agent did not know Mo", and round 9's smaller models make that worse. So the opposite hypothesis deserves a fair run: a familiar language plus Mo's runtime and checks beats a novel language. Round 10 (Elixir) is one version. A sharper one: the same agent writes the same program twice, the second time with its first program in context, and the loop difference is the unfamiliarity tax. If the tax is most of the cost, the right design may be Mo's runtime under a syntax models already know, and that is better found in week two than in year two.

## Flagged, not proposed yet

A compiler pass that is a model: each function carries an intent line, and a second, independent model checks the body against it as a diagnostic in `mo check`. Non-deterministic, so never a law. Whether an intent check catches what the hidden suite catches is measurable; it ranks after the five above because those settle whether the foundation holds.

## Order

1 and 3 reuse round 7's programs and slot into the pause after round 8; 5 starts with round 8; 2 is a day's experiment whenever a pane is free; 4 waits for program 7 or a planted fault in the ledger. Asked which of the five would change his mind most if it came out against Mo, Robert (15 Sep, 21:30): not sure; Fable's answer, bodies as cache, orders the five. All five locked the same evening; 1, 2, and 3 have run ([[bodies-as-cache]], [[sampling-as-verification]], [[erosion-round]]).

## Related
- [[bodies-as-cache]], [[sampling-as-verification]], [[erosion-round]] (measurements 1, 2, 3 as run)
- [[d38-time-travel-debugging]], [[d40-structured-runtime-events]] (what measurement 4 decides)
- [[d42-elixir-round]]
- [[d41-small-model-round]]
- `spec/design-v0/01-premise.md`, the thesis
- `spec/design-v0/08-milestone.md`, the measure
- [[roadmap]]
