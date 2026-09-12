# Mo Lang — Session Handoff

Written 12 Sep 2026 at the end of session 1; refreshed during session 2. Read this first in any new session.

## What this project is

Robert and Claude are co-designing **Mo**, a from-scratch programming language for the AI era. Equal partners: Claude is thinking partner, idea generator, and expert; Robert (10+ years SWE, first language) decides by taste. Founding premise: agents write ~100% of code, humans read only at a high "spec altitude." Rethink old, proven ideas (Tiger Style, NASA Power of 10, contracts, simulation testing) AI-first instead of human-first.

## Where everything lives

- **Mo Lang hub (Notion, the front door: status, page map, session log):**
  https://app.notion.com/p/3d96bcfa7c7581c99fddeecb9c495c5e
  Page ID `3d96bcfa-7c75-81c9-9fdd-eecb9c495c5e`. Every Mo page is nested under it. Read its "Where new things go" section before creating any Notion page.
- **Design Journal (Notion, the record of everything agreed):**
  https://app.notion.com/p/3d96bcfa7c75815e9d88f6b686b43c6c
  Page ID `3d96bcfa-7c75-815e-9d88-f6b686b43c6c`
- **Open Questions & Recommendations (Notion, the decision queue):**
  https://app.notion.com/p/3d96bcfa7c7581288f6bfde6a5b81865
  Page ID `3d96bcfa-7c75-8128-8f6b-fde6a5b81865`
- **Decisions (Notion, empty until the v0 lock):** https://app.notion.com/p/3d96bcfa7c7581a5ae50e621ee3c9c1d
- **Research (Notion, one sub-page per researched topic):** https://app.notion.com/p/3d96bcfa7c758165987ce2b0d2de0da3
- All private in Robert's Notion. Fetch the hub, the Journal, and Open Questions with `notion-fetch` before doing anything.
- **This repo** (`~/Projects/mo-lang`, git): `README.md` (map), `docs/` (design doc, grammar, error catalog), `research/` (notes with sources), `examples/` (program corpus). Notion holds conversation and decisions; the repo holds artifacts.

## How Robert wants to work (non-negotiable)

1. **One question at a time.** Never ask two.
2. **Exploration mode.** Nothing is formally decided; capture things he likes as "directions we like." Formal locking happens later in one sitting.
3. **Show code, don't describe.** He decides by seeing snippets. Give options as short code, a recommendation, the why, then one question.
4. When he says "unpack this" or "ELI5", give full reasoning with concrete code before asking again.
5. **Update the Notion journal at checkpoints**, not after every exchange. When editing Notion with `update_content`, match on distinctive plain-text fragments; numbered-list prefixes and bold-with-backticks do not match reliably.
6. Do fresh **web research** rather than relying on training data when a topic calls for it.
7. He reads on his phone; keep Notion content phone-friendly.

## His taste (learned the hard way)

- Ruby is his favorite language. Mo must be as simple and elegant as Ruby/Python: borrow what he likes, keep out what he doesn't.
- Rejected on sight: Rust/Gleam braces syntax; `def`/`end`; `end` label comments; `.with(...)` for updates; `->` case arms; `::` module paths.
- Chose: `fn name(arg: Type) : Ret ... end` blocks with no braces; bare `x = ...` immutable bindings with `var` for mutable; `case v ... Pattern: expr ... end`; `module Payments.Refund`; plain `state.count = 0` inside process `update`; `try` prefix for propagation; predicate `?` methods.
- Hates OOP and classes. Loves Elixir/BEAM, Go, Rust qualities, Elm. Wants a single static binary and a **fast compiler** (Rust's slowness is the anti-pattern).

## State of the design after session 1 (summary; the journal has all detail)

**Directions we like (27 items in the journal), in short:**
agents write ~100%; humans read at spec altitude; source carries its own evidence; style rules become compiler laws (possibly no escape hatch); never OOP; Elixir-flavored functional; BEAM qualities without the BEAM (small linked-in runtime OK, no VM); immutable by default with local `var` + `inout`; statically typed, Rust-plus-refinements from day one; concurrency at the edges like Go; processes are the only identity, each an Elm-shaped state machine (state + messages + pure `update`); effects via capability parameters, no effect type system; direct-style I/O with runtime interception, green threads, no async keyword; every effectful call has a mandatory deadline; two failure kinds (expected = `Error` value, bug = process crash), **no try-catch**, supervisor restart, agent fixes crashes autonomously with no human; negative space (`never` clauses) is the human-agent contract, humans speak it, agents write it, humans read it, humans pulled in only when the shape changes; compile speed is a hard requirement; interpreter for the edit loop, C via Zig for release, native backend only if proven necessary.

**Syntax pieces chosen (15, in the journal under "Syntax picks, piece by piece")** and a **current base example** in Robert's style is in the journal. A regenerated full example with all picks applied is in Part B of the Open Questions page.

## Where we stopped

**Session 2 (12 Sep 2026):** Q1–Q10 answered, all **in**, recorded with ✅ on the Open Questions page. Q10 (ID-addressed editing) was unpacked in full; it is now direction 29 and its own Journal section. Robert added two standing principles: **nothing is final until measured** (direction 28: benchmarks/evals for every performance claim) and **supply-chain security is a first-class goal** (direction 30, new **Q17** on package management). Q11–Q17 have ✍️ answer lines on the Open Questions page; Robert was answering them on his phone.

**Next:** fetch the Open Questions page, read Robert's Q11–Q17 answers, fold them into the Journal (✅ lines + directions), then start Part D step 1: the design document v0 in `docs/design-v0.md`. Q17 needs a research pass (`research/supply-chain.md`) before a recommendation.

## Prompt to paste into the new session

> We're continuing the Mo language design. Read `HANDOFF.md` in this directory, then fetch the Notion hub, Design Journal, and Open Questions pages it links. Pick up from "Where we stopped" and "Next" in the handoff. One question per message; capture in Notion at checkpoints.
