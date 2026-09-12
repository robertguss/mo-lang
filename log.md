# Wiki Log

> Chronological record of all vault actions. Append-only.
> Format: `## [YYYY-MM-DD] action | subject`
> Actions: create, ingest, update, query, lint, archive, session
> Rotate to `log-YYYY.md` past 500 entries.

## [2026-09-12] create | Vault initialized
- Domain: the Mo language design (see SCHEMA.md)
- Migrated from two Notion pages in Robert's work workspace, exported verbatim to `raw/notion/design-journal-2026-09-12.md` and `raw/notion/open-questions-2026-09-12.md` with sha256.
- Generated 80 pages: 30 directions, 17 questions, 15 syntax picks + 4 examples + 1 overview, 12 deep dives, 1 plan, 2 sessions. Every page carries frontmatter, a Related list, and auto-links for "direction N" / "QN" / "piece N".
- Conventions adapted from the Hermes `llm-wiki` skill (`.claude/skills/llm-wiki/SKILL.md`): page types swapped to direction / question / decision / syntax-pick / example / deep-dive / plan / session / comparison / concept.
- Tooling: `tools/lint.py`; `qmd` collection `mo-lang` with embeddings.

## [2026-09-12] session | Session 2
- Q1–Q10 answered (in). Directions 28–30 added. Q17 added. Q11–Q17 pending.
- See sessions/session-02.md.

## [2026-09-12] update | Q11–Q16 answered
- Q11 in (after unpacking "platform"), Q12 counter (70 lines, not 40), Q13 in, Q14 in + program menu, Q15 in (keep Mo, no story), Q16 in.
- Created plans/program-menu.md. Files: questions/q11–q16, plans/program-menu.md, plans/roadmap.md, index.md.

## [2026-09-12] update | Q17 ordering + research lanes
- Q17: ordering B (design-v0 first, research in parallel). Robert will run deep-research prompts with his own tools; academic papers required. SCHEMA "Research" flow updated; research/prompts/ and raw/research-runs/ created; first prompts filed.

## [2026-09-12] ingest | agentlanguages.dev catalogue + language landscape survey
- raw/articles/agentlanguages-dev-catalogue-2026-09-12.md (42 agent-native languages, three camps).
- research/concepts/language-landscape.md: 40+ languages in seven groups, 33 cited sources, proposed 13-entry shortlist for the comparison pass. arXiv rate-limited this pass; paper sweep deferred to Exa + Robert's lane.
- research/prompts/prompts-language-landscape.md for Robert. Prompt pages renamed with a prompts- prefix to avoid slug collisions.

## [2026-09-12] update | Comparison-pass shortlist approved; Exa wired in
- Robert approved the 13-entry shortlist in research/concepts/language-landscape.md. Comparison pages go in research/comparisons/, one per entry.
- tools/exa.py: search / contents / answer / research against Exa (key in ~/.zshenv, never in the repo). First Exa query surfaced Neam and NTNT, absent from the agentlanguages.dev catalogue — to be checked.

## [2026-09-12] create | plans/comparison-pass.md
- Brief for an Opus worker session run via Herdr: template, tools, 13 briefs, order, done-criteria.
