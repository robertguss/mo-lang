# Mo Lang — Session Handoff

Written 12 Sep 2026 at the end of session 1; rewritten during session 2 when the record moved from Notion to this vault. Read this first in any new session.

## What this project is

Robert and Claude are co-designing **Mo**, a from-scratch programming language for the AI era. Equal partners: Claude is thinking partner, idea generator, and expert; Robert (10+ years SWE, first language) decides by taste. Founding premise: agents write ~100% of code, humans read only at a high "spec altitude." Rethink old, proven ideas (Tiger Style, NASA Power of 10, contracts, simulation testing) AI-first instead of human-first.

## Where everything lives

**This repo is the record.** It is a git repo and an Obsidian vault following the LLM-wiki pattern. Notion is retired for this project (it was Robert's *work* workspace; the two pages were exported verbatim to `raw/notion/` and are to be deleted by Robert).

Orientation at the start of every session, in this order:
1. `SCHEMA.md` — layout, page types, frontmatter, tag taxonomy, how work flows through the vault.
2. `index.md` — every page, one line each.
3. `log.md` — last 20 entries.
4. `sessions/` — the most recent session page.

The skill that defines the wiki conventions is at `.claude/skills/llm-wiki/SKILL.md` (Hermes `llm-wiki`, adapted). Search with `qmd query "..."` (collection `mo-lang`). Lint with `python3 tools/lint.py`.

## How Robert wants to work (non-negotiable)

1. **One question at a time.** Never ask two.
2. **Exploration mode.** Nothing is formally decided; capture things he likes as directions. Formal locking happens later in one sitting (→ `decisions/`).
3. **Show code, don't describe.** Options as short code, a recommendation, the why, then one question.
4. "Unpack this" / "ELI5" → full reasoning with concrete code before asking again.
5. **Update the vault at checkpoints**, not after every exchange: edit pages, bump `updated:`, update `index.md` if pages were added, one `log.md` entry, commit.
6. Fresh **web research** over training data when a topic calls for it; save sources to `raw/`.
7. He reads on his phone (Obsidian mobile); keep pages short, snippets under 20 lines, no wide tables.
8. **Nothing is final until measured** (direction 28). Performance claims are hypotheses with a named check.

## His taste (learned the hard way)

- Ruby is his favorite language. Mo must be as simple and elegant as Ruby/Python: borrow what he likes, keep out what he doesn't.
- Rejected on sight: Rust/Gleam braces syntax; `def`/`end`; `end` label comments; `.with(...)` for updates; `->` case arms; `::` module paths.
- Chose: `fn name(arg: Type) : Ret ... end` blocks with no braces; bare `x = ...` immutable bindings with `var` for mutable; `case v ... Pattern: expr ... end`; `module Payments.Refund`; plain `state.count = 0` inside process `update`; `try` prefix for propagation; predicate `?` methods.
- Hates OOP and classes. Loves Elixir/BEAM, Go, Rust qualities, Elm. Wants a single static binary and a **fast compiler** (Rust's slowness is the anti-pattern).
- Cares a lot about **supply-chain security** (direction 30, Q17) and a Go-like batteries-included stdlib.

## State of the design

30 directions in `directions/`, 15 syntax picks in `syntax/`, 12 deep dives in `deep-dives/`. Q1–Q10 answered **in** (see each `questions/qNN-*.md`, `answer:` in frontmatter). The current base example is `syntax/base-example.md`; the fuller one with Q1–Q7 applied is `syntax/full-example-q1-q7.md`.

## Where we stopped (comparison pass, 12 Sep 2026)

A worker session (Opus) ran the comparison pass from `plans/comparison-pass.md`. Done:
- 13 pages in `research/comparisons/`: elixir, go, rust, roc, koka, austral, hylo, unison, moonbit, bosque, spark-ada-and-dafny, agent-native-cluster, verse. Each is cited through the shared ledger `research/comparisons/.ledger.json` (124 sources), with raw sources in `raw/articles/` and `raw/papers/`.
- `research/concepts/comparison-synthesis-draft.md`: 7 ⚠️ tensions with existing pages, top ten steals, and about 20 open questions for Robert. **A draft for Fable to finish, not a decision.**
- `index.md`, `log.md` and the plan's Progress list are updated; lint is clean; everything is committed and pushed.
- No page under `directions/`, `questions/` or `syntax/` was edited. Contradictions are surfaced with ⚠️ on the comparison pages only.

The earlier session-2 state is in `sessions/session-02.md`. Q1–Q17 are answered (see `index.md`).

## Next

1. Walk Robert through the 7 ⚠️ tensions in `research/concepts/comparison-synthesis-draft.md`, one per message, recommendation each. Record answers on the pages they touch (a `## Session 3` note under the direction/question) — never rewrite history.
2. Then the synthesis draft's open questions, ordered by Fable.
3. Q17 recommendation from `research/concepts/supply-chain-defenses.md` (six design options, all evidence in place; the closure-capture hole must be settled first — it's tension 1).
4. Then `docs/design-v0.md`, which must answer `research/concepts/case-against-new-languages.md`.
5. Housekeeping: Robert still owes the Notion deletions. All six of Robert's Perplexity runs are ingested and synthesized.

**Cost rule (Robert):** mechanical research/writing goes to an Opus worker session in Herdr (`herdr agent start worker --kind claude --pane <id> -- --model opus --dangerously-skip-permissions`; answer the trust dialog with `down enter`; give it a plan page like `plans/comparison-pass.md`). Fable keeps judgment: tensions, synthesis, Q17, design-v0. Both share one working tree, so `git pull --rebase --autostash` before pushing.

## Prompt to paste into the new session

> We're continuing the Mo language design. Read `HANDOFF.md`, then `SCHEMA.md`, `index.md`, the tail of `log.md`, and the latest `sessions/` page. Pick up from "Next" in the handoff. One question per message; checkpoint the vault and commit at natural breaks.
