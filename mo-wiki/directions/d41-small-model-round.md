---
title: "Direction 41: The small-model round"
created: 2026-09-15
updated: 2026-09-15
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

After round 8, as round 9. Several models of different sizes, open-weights models among them, not one small Claude: the spread is the insight. Recorded in the decision log as locked.

## Shape

The same pre-registered task and hidden suite as a finished round (round 7's job queue, or round 8's change), three languages, one small model in all three panes, predictions on the page before any session starts. Candidates, one row each on the plan: a small Claude (Haiku 4.5 through Claude Code's `--model`), a mid one (Sonnet 5), and two or three open-weights models of different sizes, driven through the agent kinds Herdr already has (`opencode`, `pi`, `kimi`, `hermes`, and the `grok` and `codex` kinds the [[model-bakeoff|bake-off]] used), served from a hosted API or a local server, Robert's call. Loops, defects, and where the time went, read against round 7's Opus rows.

## Related
- [[model-bakeoff]]
- [[control-run-7]]
- [[roadmap]]
- [[decision-log]]
