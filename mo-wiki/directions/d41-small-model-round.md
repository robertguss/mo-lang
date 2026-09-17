---
title: "Direction 41: The small-model round"
created: 2026-09-15
updated: 2026-09-17
type: direction
tags: [agents, verification, roadmap]
sources: [decisions/decision-log.md, plans/control-run-7.md, plans/model-bakeoff.md]
number: 41
status: locked
origin: "Robert, 15 Sep 2026"
confidence: medium
---

# Direction 41: The small-model round

Robert, 15 Sep 2026, morning: the worker in every program and every control round has been Opus, a frontier model. He wants some of the measurements rerun with much smaller, less expensive, less powerful models, open-weights ones included, and the results compared, since Mo's standing against Go and Python may owe something to the model writing it.

## Fable's reading

The measure (chapter 8) has five columns. Three do not move with the model: native speed and memory are the toolchain's, and the dependency count is the language's. Two do: reliability under the hidden defect suite, and the loop count. A weaker model makes more mistakes, and a mistake is what a check exists to catch; six programs and seven rounds with Opus have shown no check catching a bug the tests would not have, and one reading of that is that Opus rarely makes the mistakes the checks are for. So the small-model round is a stronger test of the reliability claim than another Opus round, not a weaker one.

## Robert's call (15 Sep, midday)

After round 8, as round 9. Several models of different sizes, open-weights models among them, not one small Claude: the spread is the insight. Recorded in the decision log as locked. Later the same day: every model runs in the Pi harness (small system prompt, close to the raw model); the models come from his Grok, Codex, and Ollama cloud subscriptions; nothing runs on this VM; smaller open-weights models may run on his MacBook Pro (96 GB). The Opus baseline is rerun in Pi too, so the harness is the same in every row.

## Shape

The same pre-registered task and hidden suite as a finished round (round 7's job queue, or round 8's change), three languages, one small model in all three panes, predictions on the page before any session starts. Candidates, one row each on the plan: a small Claude (Haiku 4.5 through Claude Code's `--model`), a mid one (Sonnet 5), and two or three open-weights models of different sizes, driven through the agent kinds Herdr already has (`opencode`, `pi`, `kimi`, `hermes`, and the `grok` and `codex` kinds the [[model-bakeoff|bake-off]] used), served from a hosted API or a local server, Robert's call. Loops, defects, and where the time went, read against round 7's Opus rows.

## What happened (round 9, 15 to 16 Sep)

Run as [[control-run-9]] on round 8's change with kimi-k3, deepseek-v4-flash, gpt-5.5, a local 27B, and Haiku 4.5 in the Pi harness. Reliability moved with the model on the Mo side only: gpt-5.5 matched Opus at zero defects, the open-weights models shipped one and two, all on a scheduling case no check states; every Go change carried the same spec-reading defect regardless of model; the local 27B wrote nothing in any language; Haiku 4.5 was wrong in every language in under ten minutes. The diagnostics carried the weaker models to green (first fix right in 21 of 23 loops) but not to right. The row for the language page: the missing check is a program `never`, a spec row, not a law. The Opus-in-Pi baseline waits on a key.

## Related
- [[control-run-9]] (the round as run)
- [[model-bakeoff]]
- [[control-run-7]]
- [[roadmap]]
- [[decision-log]]
