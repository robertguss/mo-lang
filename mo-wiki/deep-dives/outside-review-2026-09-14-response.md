---
title: "Outside review, 14 Sep 2026: Fable's response"
created: 2026-09-14
updated: 2026-09-14
type: deep-dive
tags: [meta, laws, processes, verification, roadmap, security]
sources: [deep-dives/outside-review-2026-09-14.md, decisions/decision-log.md, plans/control-run-6.md, plans/interpreter-step-27.md, spec/design-v0/02-laws.md, spec/design-v0/08-milestone.md]
confidence: medium
contested: true
contradictions: [outside-review-2026-09-14]
---

# Outside review, 14 Sep 2026: Fable's response

The review ([[outside-review-2026-09-14]]) read the vault as it stood before step 27 and before Robert's reframing of the control run, both of which landed the same afternoon. Sorted by what to do about each point.

## Already done when the review arrived

- The 500-line file law is gone, not demoted: chapter 2 forbids warnings, so it had to go ([[interpreter-step-27]], part A).
- `state`, `result`, and `old` are contextual keywords, reserved only inside a process, an `ensures`, or an `invariant`, and names everywhere else: the "contextual keywords with strong lookahead" the review asks for (part B). Sigils would be a worse cure than the disease and against Robert's taste.
- The `never` reading a `var` between two field assignments is fixed as the review recommends: a `never` reads values at rest (part C).
- Robert reframed the control run (chapter 8, Session 6): reliability first, then native speed and memory, the feedback loop, and the dependency count; agent time is a recorded column. The review's central complaint, that round 6 measured agent minutes on programs that do not exercise Mo's differentiators, is the same conclusion.

## Wrong on facts

- The C backend exists since step 13 (`mo build`, C11 through `zig cc` to a static binary); every "native" number in round 6 came from it. The gap to Go (192 MiB to 73, 14 s to 7.3 on the replay, 399 to 858 pairs a second) is inside the backend and the runtime (one fsync per record, the region allocator) and in the program (a quadratic re-lease), which is a harder problem than a missing backend.
- The corpus is 154 files, not 68. The point stands: compile speed at 5,000 files is unmeasured. A generated-corpus benchmark is one small step.

## Agreed, to act on

1. **The shape numbers.** The laws that remove a class of bug stay (bounded loops, bounded mailboxes, deadlines, overflow, capabilities, the honesty laws). The counted ones (70 lines a function, 6 parameters, nesting 3, 12 state fields) become project-configurable settings with today's defaults, still errors, never warnings. Robert's call, since the laws are his; a row for him.
2. **The `try` law is overstated.** `try` is Rust's `?` by another name. Chapter 2 should say "no unwrap, no panic, no catch" rather than "no exceptions". Fable owns the chapter and rewords it.
3. **Zero dependencies is the largest unaccounted cost.** Recipes cover small pure modules. TLS, crypto, a Postgres driver, compression, HTTP/2 are years of stdlib, which Go carried with a team. Mo's bet is that agents write bricks under a spec with the capability model as the audit; untested and unpriced. Needs its own page and a decision before program 7.
4. **Program 7 exercises what Mo is for.** This corrects Fable's own candidates of the same afternoon: CommonMark tests parsing and says nothing about capabilities, recipes, or the runtime surface. Program 7 reimplements a real tool whose original carries third-party dependencies and runs as a service, so the dependency count, the capability manifest, and the runtime surface are all exercised.
5. **Closures (d31).** A bet to watch, not change: round 7's reading gains a column, "wanted a closure, wrote a struct".
6. **Compile speed at scale.** A generated corpus of 5,000 modules with cross-module `use` lines, benched once, before the agent-loop claim is made again.
7. **The process as an artifact.** The `mo-lead` skill and the decision-log practice are worth a page other projects can copy; later.

## Disagreed

- A JSON `verified:` line: the `.mo.ids` sidecar already holds the machine-readable record; the line is for the human reader.
- "Ruby's look": mechanically the syntax is Elixir-shaped, and outward-facing text should say so; the picks are Robert's taste and change nothing in the language.

## The fork

The review says the vault frames "agents write better code with the compiler as teacher" while building "an agent-native runtime with capabilities, supervision, events, and a language shaped to expose it". Accurate. Robert's reframing of 14 Sep already moved toward the second. If the second is the thesis, chapter 1 says so, program 7 is chosen for it, and the control run's competitor becomes the BEAM rather than Go with contracts bolted on. Put to Robert as one question the same afternoon.

## Related
- [[reading-pack-2026-09]]
- [[outside-review-2026-09-14]]
- [[outside-review-2026-09-13-response]]
- [[control-run-6]]
- [[control-run-7]]
- [[interpreter-step-27]]
- [[decision-log]]
