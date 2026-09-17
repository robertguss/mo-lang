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

## Later in the session (after the vault was built)

- Q11–Q17 answered: Q11 in (after unpacking "platform"), **Q12 counter: 70 lines, not 40**, Q13 in, Q14 in plus a [[program-menu]], Q15 in (keep Mo, no story), Q16 in, Q17 ordering: research first.
- Robert: **research before the design doc**, not after; a broader survey of languages old, obscure, and brand-new; papers included; he runs deep-research prompts himself (Perplexity) and I write them → two-lane research, `research/prompts/` and `raw/research-runs/`.
- Landscape survey → [[language-landscape]]; agentlanguages.dev catalogue (42 agent-native languages) ingested; Exa wired in (`tools/exa.py`).
- Robert: use a cheaper model for mechanical work. An **Opus worker session run via Herdr** wrote the 13 comparison pages from [[comparison-pass]], the [[comparison-synthesis-draft]] (7 ⚠️ tensions, 10 steals, ~20 questions), then [[supply-chain-defenses]] and [[landscape-second-lane]] from Robert's six Perplexity runs, then Motoko, [[case-against-new-languages]], [[capability-module-lineage]], and refreshes.
- Robert's lane caught two stale facts in mine (Gleam version; MoonBit's Rust benchmark, refuted) and produced the "three kinds of cost" framing: annotation cost collapses when agents write code; proof, runtime, and cultural costs don't.

## Decided about how we work

- Vault in the repo is the record. Notion is retired for this project once Robert deletes the work-Notion pages.
- Checkpoint = edit pages, bump `updated:`, index, one log entry, commit. See `SCHEMA.md` for the flow.

## Next

1. Fable walks Robert through the 7 ⚠️ tensions in [[comparison-synthesis-draft]], one per message, with a recommendation each; then the open questions it lists.
2. Fable finishes the synthesis and the Q17 recommendation from [[supply-chain-defenses]].
3. Then [[roadmap]] step 1: `spec/design-v0.md` (now the folder `spec/design-v0/`), which must also answer [[case-against-new-languages]].
4. Notion pages: still to be deleted by Robert (left alone on his request).

## Related
- [[session-01]]
- [[roadmap]]
- [[d28-nothing-final-until-measured]]
