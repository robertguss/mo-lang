# Mo

A from-scratch programming language for the AI era, co-designed by Robert Guss and Claude.

**Premise:** agents write ~100% of the code; humans read only at the "spec altitude" (intent, contracts, `never` clauses, effects). Ruby's look, Go's discipline, BEAM's fault tolerance without the VM, and every style rule turned into a compiler law.

## This repo is the record

It is a monorepo: the design wiki in `wiki/` (an Obsidian vault, the only part Obsidian syncs), the spec in `docs/`, the Mo corpus in `examples/`, and later the Zig toolchain in `toolchain/`. The design lives here as a wiki of small linked markdown pages following [Karpathy's LLM-wiki pattern](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f): Claude maintains it, Robert reads and decides.

| Start here | |
|---|---|
| `wiki/SCHEMA.md` | how the vault is organized and the conventions (read first) |
| `wiki/index.md` | every page, one line each |
| `wiki/log.md` | what changed, when |
| `HANDOFF.md` | the prompt that starts the next session |

| The design | |
|---|---|
| `wiki/directions/` | the 35 "directions we like" — not yet decisions |
| `wiki/questions/` | Q1–Q17, each with options, recommendation, and Robert's answer |
| `wiki/decisions/` | locked rules (empty until the v0 lock) |
| `wiki/syntax/` | the 15 syntax picks and the example programs |
| `wiki/deep-dives/` | state model, effects, errors, negative space, compile speed, ID editing, the steal list… |
| `wiki/plans/` | the roadmap |
| `wiki/sessions/` | what happened in each sitting |
| `wiki/research/` | comparisons and researched concepts, backed by `raw/` sources |

| Artifacts | |
|---|---|
| `docs/` | `design-v0/` (eight chapters), grammar, laws, error catalog |
| `toolchain/` | the Zig compiler and runtime (not yet started) |
| `examples/` | the Mo program corpus |
| `wiki/raw/` | immutable sources: Notion exports, articles, papers |
| `wiki/tools/` | `lint.py` — vault health check |

## Status

Exploration phase. Session 3 (12 Sep 2026): all questions answered, the 7 research tensions resolved, packages reframed as recipes, `docs/design-v0/` drafted. Next: grammar, example corpus, then the Zig interpreter.

## Tooling

- `python3 wiki/tools/lint.py` — broken links, orphans, frontmatter, index, raw drift.
- `python3 wiki/tools/exa.py search|contents|answer|research ...` — web research via Exa (needs `EXA_API_KEY`).
- `qmd query "..."` — hybrid search over the vault (collection `mo-lang`); `qmd update && qmd embed` after adding pages.
- Open `wiki/` in Obsidian for graph view and wikilinks.
