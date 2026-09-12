---
title: "Session 2 — 12 Sep 2026"
created: 2026-09-12
updated: 2026-09-12
type: session
tags: [meta]
sources: [raw/notion/open-questions-2026-09-12.md, raw/notion/design-journal-2026-09-12.md]
date: 2026-09-12
session: 2
---

# Session 2 — 12 Sep 2026

## What happened

- Walked the Open Questions page one at a time. **Q1–Q10 answered, all in**: [[q01-comments|Q1]] comments `#`, [[q02-strings-and-interpolation|Q2]] Ruby strings, [[q03-numbers-and-units|Q3]] units as dot-call functions, [[q04-integer-types-and-overflow|Q4]] sized ints and crash-on-overflow in every build, [[q05-option-and-no-nil|Q5]] `Option` with `or` as the only shorthand, [[q06-verified-line|Q6]] toolchain-computed `verified:` line, [[q07-process-api|Q7]] typed handles and declared supervisors, [[q08-verification-tiers|Q8]] three tiers, [[q09-compiler-diagnostics|Q9]] structured diagnostics, [[q10-semantic-ids-and-editing|Q10]] ID-addressed editing.
- Robert asked for [[q10-semantic-ids-and-editing|Q10]] unpacked ("fascinating"). The unpack became [[id-addressed-editing]] and [[d29-edit-by-declaration-id|direction 29]].
- Robert added a standing principle after Q4: **nothing is final until measured** → [[d28-nothing-final-until-measured|direction 28]]. Every performance claim is a hypothesis with a named way to check it.
- Robert raised **package management and supply-chain security** as very important → [[q17-package-management-and-supply-chain|Q17]] and [[d30-supply-chain-security|direction 30]].
- Q11–Q17 given answer lines; Robert was reading them on his phone. **Still pending at session end.**
- Notion was organized under a hub page, then Robert flagged that this was his *work* Notion and the project must be under his own control. Options weighed: personal Notion / Obsidian vault in the repo / Karpathy's LLM-wiki pattern on top of that vault. **Robert: in on the vault + LLM-wiki conventions**, reading on the Obsidian mobile app, private GitHub for sync.
- Built this vault: both Notion pages exported verbatim to `raw/notion/`, 80 wiki pages generated from them, `SCHEMA.md`, `index.md`, `log.md`, `tools/lint.py`. Installed `qmd` (Robert's suggestion) with the repo as a collection.
- Robert accidentally trashed `.claude/` (the llm-wiki skill); restored with `trash-restore`.

## Decided about how we work

- Vault in the repo is the record. Notion is retired for this project once Robert deletes the work-Notion pages.
- Checkpoint = edit pages, bump `updated:`, index, one log entry, commit. See `SCHEMA.md` for the flow.

## Next

1. Robert answers Q11–Q17 (chat or by editing the question pages).
2. Fold answers in; then [[roadmap]] step 1: `docs/design-v0.md`.
3. [[q17-package-management-and-supply-chain|Q17]] needs a research pass (`research/concepts/supply-chain-attacks-2025-26.md`) before a recommendation.
4. Push to a private GitHub repo (`gh auth login` needed from Robert).

## Related
- [[session-01]]
- [[roadmap]]
- [[d28-nothing-final-until-measured]]
