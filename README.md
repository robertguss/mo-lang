# Mo

A from-scratch programming language for the AI era, co-designed by Robert Guss and Claude.

**Premise:** agents write ~100% of the code; humans read only at the "spec altitude" (intent, contracts, `never` clauses, effects). Ruby's look, Go's discipline, BEAM's fault tolerance without the VM, and every style rule turned into a compiler law.

## This repo is the record

It is a git repo, an Obsidian vault, and (later) the toolchain's source tree, all at once. The design lives here as a wiki of small linked markdown pages following [Karpathy's LLM-wiki pattern](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f): Claude maintains it, Robert reads and decides.

| Start here | |
|---|---|
| `SCHEMA.md` | how the vault is organized and the conventions (read first) |
| `index.md` | every page, one line each |
| `log.md` | what changed, when |
| `HANDOFF.md` | for Claude: where the last session stopped, what's next |

| The design | |
|---|---|
| `directions/` | the 30 "directions we like" — not yet decisions |
| `questions/` | Q1–Q17, each with options, recommendation, and Robert's answer |
| `decisions/` | locked rules (empty until the v0 lock) |
| `syntax/` | the 15 syntax picks and the example programs |
| `deep-dives/` | state model, effects, errors, negative space, compile speed, ID editing, the steal list… |
| `plans/` | the roadmap |
| `sessions/` | what happened in each sitting |
| `research/` | comparisons and researched concepts, backed by `raw/` sources |

| Artifacts | |
|---|---|
| `docs/` | design doc v0, grammar, laws, error catalog |
| `examples/` | the Mo program corpus |
| `raw/` | immutable sources: Notion exports, articles, papers |
| `tools/` | `lint.py` — vault health check |

## Status

Exploration phase. Session 2 (12 Sep 2026): Q1–Q10 answered (all in), Q11–Q17 pending. Next: fold in the answers, then `docs/design-v0.md`.

## Tooling

- `python3 tools/lint.py` — broken links, orphans, frontmatter, index, raw drift.
- `python3 tools/exa.py search|contents|answer|research ...` — web research via Exa (needs `EXA_API_KEY`).
- `qmd query "..."` — hybrid search over the vault (collection `mo-lang`); `qmd update && qmd embed` after adding pages.
- Open the repo root in Obsidian for graph view and wikilinks.
