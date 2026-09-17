---
title: "Direction 42: The Elixir round, the null hypothesis run"
created: 2026-09-15
updated: 2026-09-17
type: direction
tags: [runtime, verification, roadmap]
sources: [spec/design-v0/01-premise.md, decisions/decision-log.md, plans/control-run-7.md]
number: 42
status: locked
origin: "Robert, 15 Sep 2026, on Fable's recommendation"
confidence: medium
---

# Direction 42: The Elixir round, the null hypothesis run

Robert, 15 Sep 2026, evening: the round after round 9 puts the BEAM in a pane. The premise (chapter 1) names the BEAM with Elixir as the null hypothesis: it already gives isolated processes, supervision, a mailbox per process, hot code loading, and a live shell. That hypothesis has only been argued on paper. Every control round so far compared Mo with Go and Python, neither of which has Mo's process model, so none has tested the runtime layer, the one the thesis says carries the most.

## Fable's reading

The round is round 7's shape with a fourth language: the same pre-registered job queue, the same hidden defect suite, one fresh agent `mo-rN-elixir` in a pane, Elixir with the checks its ecosystem offers (dialyzer, credo, ExUnit), the dependency count read as every Hex package the program needs at run time plus its tools. The columns that decide: reliability under the suite, the loop time, the dependency count, and the runtime rows Mo claims as its delta (a kill under load loses no acknowledged write; a `:never` child stays down; memory under 100k jobs; the 1M replay). Round 8's maintenance change runs on the Elixir program too, so the regression column exists for it.

What a result means. If Elixir matches Mo on reliability and the runtime rows, Mo's delta over the BEAM is what it claims in the premise and nothing more: static types at every boundary, capabilities that cannot be forged, a deadline on every wait, one static binary, no package ecosystem to trust; and each of those has to be measured on its own or dropped. If Elixir falls behind on the suite or the runtime rows, the process model is not enough and the language layer earns its place. Either way the pause after round 8 reads against this round, so its plan is written at that pause.

## What happened (round 10, 16 Sep)

Run as [[control-run-10]]: one fresh Opus session wrote the queue in Elixir from round 7's spec, a second made round 8's change. Elixir held reliability on the first program and carried two defect causes on the changed one against Mo's zero; it took the speed column and the time to write, tied on dependencies read chapter 1's way, and its supervisor answered P6, the kill under load, from a 70-line `rest_for_one` the program never thought about, where Mo's spec-as-written queue had stopped answering in round 8. The BEAM's row is answered since by Mo's change 3 queue ([[erosion-round]], generation three: back in 106 ms) and by chapter 10 §1 and §2. Elixir is the fourth language of the erosion round from generation two on.

## Related
- [[control-run-10]] (the round as run)
- chapter 1 (`spec/design-v0/01-premise.md`) (the null hypothesis)
- [[d41-small-model-round]] (round 9, before this)
- [[control-run-7]] (the shape it copies)
- [[roadmap]]
