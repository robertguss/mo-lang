---
title: "Reading pack for an outside reviewer, September 2026"
created: 2026-09-14
updated: 2026-09-14
type: deep-dive
tags: [meta, roadmap, research]
sources: [spec/design-v0/01-premise.md, spec/design-v0/03-semantics.md, spec/design-v0/06-packages.md, deep-dives/outside-review-2026-09-14.md, plans/control-run-6.md, plans/control-run-7.md, decisions/decision-log.md]
confidence: medium
---

# Reading pack for an outside reviewer

For a reader from the Erlang and OTP world, and one who has built a capability system (Pony, Wyvern, Newspeak, E). One sitting, in this order; the appendix is there so a reviewer does not re-suggest what was already tried. Everything is in this repository; nothing is private.

## Read, in order

1. **The thesis**: `spec/design-v0/01-premise.md`. Three layers, the runtime first; the BEAM as the null hypothesis. Ten minutes.
2. **The failure model**: `spec/design-v0/03-semantics.md`, the "What a crash discards" section onward. What a timeout leaves, what restart loses, when a reply is durable, poison, overload. This is the page an OTP reader should attack.
3. **Capabilities and packages**: `spec/design-v0/06-packages.md`, then `directions/d34-packages-are-recipes.md` and `research/concepts/` on supply-chain attacks. This is the page a capability-systems reader should attack: authority as a parameter, obtained only at `main`, recipes at spec altitude, bricks as audited platform code.
4. **The two reviews so far**: [[outside-review-2026-09-13]] with [[outside-review-2026-09-13-response]], and [[outside-review-2026-09-14]] with [[outside-review-2026-09-14-response]]. The second reviewer's replies are summarized in the decision log rows of 14 Sep afternoon.
5. **The evidence**: [[control-run-6]] (the round Mo lost on the old measure, all four predictions) and [[control-run-7]] (the round on the new measure, all four held, reliability level). Read the Result tables, not the prose, first.
6. **A program**: `examples/programs/jobq/` (nine modules, the durable job queue) with `examples/README.md`'s two rules. Read `queue.mo`'s `update`, the `never`s, and the `verified:` lines; skip bodies as Robert does.
7. **The working agreements**: `mo-wiki/SCHEMA.md`, the "Working agreements with Robert" section, and the decision-log conventions. The process is part of what is under review.

## What we want from you

- OTP reader: where does chapter 3 promise something the BEAM learned not to promise? Where is a deadline on every wait, a bound on every mailbox, or "a bug crashes the process" going to hurt a long-running service in a way our programs have not shown? Is the runtime surface (directions 37 and 40) something you would use, or a debugger by another name?
- Capability reader: is `main` as the only source of authority, with narrowing (`fs.read_only`, `scoped`) and the checker following a capability through parameters, start arguments, message fields, and branches (`MO0404`), sound? Where does it leak? Is "a recipe's bodies are generated and checked against its tests" a package model or a hope?
- Both: what would you measure that rounds 6 and 7 did not?

## Appendix: tried and rejected

Pulled from the decision log's overturned, dropped, and narrowed rows, so they are not suggested again.

| tried | when | what happened |
|---|---|---|
| Memoizing pure calls in the interpreter | step 12 | reversed in step 12b: the reference interpreter runs every body every time |
| Checking `never` blocks only under `--sim` | step 12 | reversed in 12b: every `never` runs at the end of every test |
| Contracts off by default in `mo build` | step 13 | overturned on acceptance: contracts run in every build, `--no-contracts` for measurement only |
| A handle can never live in a value | step 18 | narrowed in step 24: a process's `state` field may hold a `Handle(T)`; structs, enums, and returns still cannot |
| No timers: a lease is a deadline checked at the next look | program 1 | kept, and `send(msg, delay:)` added in step 24 after three programs asked |
| The one-line `if` refused, with a `mo fix` back to the block form | step 21 | reversed in step 25: the one-line `if` is a value (pick 16); step 26 made it the value in tail position |
| `state`, `result`, `old` as reserved words everywhere | v0 | narrowed in steps 25 to 27: keywords only in the positions the grammar reserves |
| A 500-line file law | v0 | dropped after round 6: a shape law cost a loop and no check earned one; the honesty laws forbid warnings, so it went rather than softened |
| A `never` reading every value a run held, a `var` between statements included | v0 | narrowed in step 27: a `never` reads values at rest |
| Agent time to green as the control run's measure | rounds 1 to 6 | dropped by Robert after round 6: no model has seen Mo; the measure is reliability, speed, the loop, dependencies |
| "Agents write better code with the compiler as teacher" as the premise | v0 | demoted in session 6 to the language layer's hypothesis; the runtime is the thesis |
| Rust or Gleam braces, `def`/`end`, `->` arms, `::` paths, a 40-line function limit | sessions 1 to 3 | rejected by Robert on sight; `fn ... end`, `case ... end`, `Module.Path`, 70 lines |
| Phone-fit as a design criterion | session 3 | rejected firmly; never used since |
| Notion as the vault | sessions 1 to 2 | retired; the Obsidian vault in `mo-wiki/` is the record |
| A registry with third-party packages as code | Q17 | not built; packages are recipes, code comes from bricks or is generated against the recipe's tests |

## Related
- [[outside-review-2026-09-14-response]]
- [[control-run-7]]
- [[decision-log]]
- [[roadmap]]
