# Mo Lang Wiki — Schema

Read this first, every session. Then `index.md`, then the last 20 entries of `log.md`. Only then touch anything.

## Domain

The design of **Mo**, a from-scratch programming language for the AI era, co-designed by Robert Guss and Claude. This vault is the single record of the design: what we like, what is asked, what is decided, what we researched, and what happened in each session. It replaces the two Notion pages that held sessions 1–2 (exported verbatim into `raw/notion/`).

This repo is also the project repo: `docs/`, `examples/`, and (later) the toolchain source live alongside the wiki. Open the repo root as an Obsidian vault.

## Layout

```
SCHEMA.md            this file
index.md             every wiki page, one line each, by section
log.md               append-only action log
HANDOFF.md           session handoff for Claude (what happened, what's next)
README.md            front door for humans

directions/          one page per "direction we like" (d01–d30, numbered, never renumbered)
questions/           one page per open question (q01–q17), answer in frontmatter
decisions/           one page per locked decision (empty until the v0 lock)
syntax/              the 15 syntax picks (p01–p15) + the example programs
deep-dives/          long-form explorations of one topic
plans/               roadmap and other plans
sessions/            one page per design session
research/            comparisons/ and concepts/ — pages backed by web research
raw/                 immutable sources: notion/ exports, articles/, papers/, assets/

docs/                artifacts: design doc, grammar, laws, error catalog (not wiki pages)
examples/            the Mo program corpus (not wiki pages)
tools/               lint.py and other vault tooling
```

Wiki pages are the `.md` files in `directions/ questions/ decisions/ syntax/ deep-dives/ plans/ sessions/ research/`. Everything else is either raw, an artifact, or tooling.

## Page types

| type | lives in | what it is |
|---|---|---|
| `direction` | directions/ | an idea Robert reacted well to; not a decision. Numbered `dNN`. |
| `question` | questions/ | something needing Robert's call. Options + recommendation + why + answer. Numbered `qNN`. |
| `decision` | decisions/ | a locked rule with rationale and a "reopen if". Numbered `DNN`. |
| `syntax-pick` | syntax/ | one syntax choice Robert made, with the snippet. Numbered `pNN`. |
| `example` | syntax/ | a complete Mo program in the current style |
| `deep-dive` | deep-dives/ | full reasoning on one topic, with options weighed |
| `plan` | plans/ | a sequence of steps we intend to follow |
| `session` | sessions/ | what happened in one sitting, chronological |
| `comparison` | research/comparisons/ | Mo held against one other language or system |
| `concept` | research/concepts/ | a researched topic (e.g. supply-chain attacks 2025–26) |

## Frontmatter (required on every wiki page)

```yaml
---
title: "Direction 13: Local var with mutable value semantics"
created: 2026-09-12
updated: 2026-09-12
type: direction            # from the table above
tags: [state, syntax]      # from the taxonomy below only
sources: [raw/notion/design-journal-2026-09-12.md]
# type-specific:
number: 13                 # direction, question, syntax-pick, decision
status: liked              # direction: liked | locked | dropped
status: pending            # question: pending | answered | withdrawn
answer: in                 # question: pending | in | no | counter
origin: "Robert"           # direction: who it came from
# optional quality signals:
confidence: high | medium | low
contested: true
contradictions: [other-page-slug]
---
```

Every page starts with `# Title` matching the frontmatter title, then body, then a `## Related` list. Minimum two outbound `[[wikilinks]]` per page.

## Tag taxonomy

Add a tag here before using it. Keep it under 25.

- **Philosophy:** `philosophy`, `laws`, `meta`, `roadmap`
- **Language:** `syntax`, `types`, `state`, `effects`, `processes`, `errors`, `contracts`, `negative-space`
- **Verification & tooling:** `verification`, `compiler`, `tooling`, `runtime`, `performance`
- **Ecosystem:** `stdlib`, `security`, `agents`
- **Research:** `research`

## Conventions

- File names: lowercase, hyphens. Numbered pages keep their prefix forever (`d13-…`, `q08-…`, `p05-…`); a renumbering is a lie about history.
- Numbers are stable, so text may refer to "direction 13" or "Q8"; always also link: `[[d13-local-var-and-inout|direction 13]]`.
- Code is shown in fenced blocks with the `ruby` hint (closest highlighter to Mo's look).
- Robert's words are quoted as his; Claude's recommendations are marked as recommendations. Never blur who said what.
- Phone-friendly: short paragraphs, no wide tables (three columns max), snippets under 20 lines.
- `updated:` is bumped on every edit. `created:` never changes.
- **Provenance:** a claim that comes from a specific raw source gets `^[raw/...]` at the end of the paragraph when the page draws on 3+ sources; single-source pages rely on `sources:`.
- `raw/` is immutable. Corrections go on wiki pages. Each raw file carries `source_url`, `exported`/`ingested`, and a `sha256` of its body so drift is detectable.

## How the design work flows through the vault

1. **An idea Robert reacts well to** → new `directions/dNN-slug.md`, `status: liked`, and a line in `index.md`.
2. **Something needing his call** → new `questions/qNN-slug.md` with options, recommendation, why, and `answer: pending`. Robert answers in chat (or by editing the page on his phone). Claude sets `answer:` and `status:`, appends the settled details under a `## Answer` heading.
3. **A long unpack** → `deep-dives/slug.md`, linked from the direction or question it serves.
4. **Web research** → source saved in `raw/articles/` or `raw/papers/` with frontmatter, then a `research/concepts/` or `research/comparisons/` page that cites it.
5. **The v0 lock** → each locked rule becomes `decisions/DNN-slug.md` with `reopen if:`; the source direction gets `status: locked` and a link. History is never rewritten.
6. **Every session** → `sessions/session-NN.md` written at the end, `HANDOFF.md` refreshed, `log.md` appended.

## Checkpoints

Claude updates the vault at natural checkpoints (a question answered, a topic closed), not after every message. A checkpoint is: edit pages → bump `updated:` → update `index.md` if pages were added → append one `log.md` entry → commit.

## Update policy on conflict

When something new contradicts an existing page: keep both with dates, mark `contested: true` and `contradictions: [slug]` on both, and surface it to Robert. Directions can contradict each other; that is exactly what the lint pass is for. Nothing is silently overwritten.

## Lint

`python3 tools/lint.py` checks: broken wikilinks, orphans, index completeness, required frontmatter, tags in taxonomy, raw sha256 drift, contested/low-confidence pages, pages over 200 lines, log size. Run it at the end of every session and record the result in `log.md`.

## Search

`qmd` is installed and the repo is a collection named `mo-lang`. `qmd query "..."` for hybrid search, `qmd search "..."` for keyword. Run `qmd update && qmd embed` after a session adds pages.
