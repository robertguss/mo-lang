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

## [2026-09-12] ingest | Comparison: Elixir
- research/comparisons/elixir.md. Inference-first gradual types ("verified bugs"), OTP supervision strategies vs Q7 (no strategy field), typed processes via Gleam. ⚠️ tension with Q1 (doc comments).

## [2026-09-12] ingest | Comparison: Go
- research/comparisons/go.md. gofmt/gofix, error-syntax post-mortem (restrict `try` position?), goroutine bug study, synctest, module supply chain + BoltDB typosquat. ⚠️ Q7 unbounded mailbox vs d04.

## [2026-09-12] ingest | Comparison: Rust
- research/comparisons/rust.md. Lifetimes are where humans fail (ICSE'22), compile-time survey, Android evidence, LLM fix vs whole-program rates. Open: trait coherence.

## [2026-09-12] ingest | Comparison: Roc
- research/comparisons/roc.md. Platform header anatomy, purity by arrow, static dispatch, Zig rewrite table. ⚠️ nuance to Q13's "100x faster" reason.

## [2026-09-12] ingest | Comparison: Koka
- research/comparisons/koka.md. Effect types vs capabilities research, Perceus, fip. ⚠️ d15 wording: closures can capture capabilities. Roc page corrected to match.

## [2026-09-12] ingest | Comparison: Austral
- research/comparisons/austral.md. Linear capabilities from a root, unsafe modules, crash-the-program rationale. ⚠️ Q8 SMT prover vs d24/Q11 zero-dependency toolchain.

## [2026-09-12] ingest | Comparison: Hylo
- research/comparisons/hylo.md. Parameter conventions, exclusivity, projections, a coherence rule to adopt, colorless concurrency.

## [2026-09-12] ingest | Comparison: Unison
- research/comparisons/unison.md. Hash recipe, never-invalidated caches, coexisting versions and patches, the documented cost of dropping text, MCP tooling.

## [2026-09-12] ingest | Comparison: MoonBit
- research/comparisons/moonbit.md. Pilot, semantics-aware sampler, SeekMoon, no-resource LLM study (near-zero zero-shot) vs SWE-AGI (agents build systems with a toolchain loop).

## [2026-09-12] ingest | Comparison: Bosque
- research/comparisons/bosque.md. Design by removal, escape-free lambdas, validation levels, small-model verification, why it slowed. ⚠️ p11 loops vs Q8 tier 3.

## [2026-09-12] ingest | Comparison: SPARK Ada and Dafny
- research/comparisons/spark-ada-and-dafny.md. Executable contracts, assurance levels, contract shapes LLMs discharge, loop invariants with solver feedback. ⚠️ Q4 sized ints vs d22's Dafny-level expectation.

## [2026-09-12] ingest | Comparison: agent-native cluster
- research/comparisons/agent-native-cluster.md. 13 languages (11 catalogued + Neam, NTNT verified). Convergence: mandatory contracts + solver + runtime fallback, agent diagnostics, toolchain-served guidance.

## [2026-09-12] ingest | Comparison: Verse
- research/comparisons/verse.md. Failure/rollback vs uncatchable runtime errors (confirms d18), AutoRTFM, frozen time, structured concurrency. Transactions complement, not replace, crash-and-restart.

## [2026-09-12] create | Comparison synthesis draft; comparison pass done
- research/concepts/comparison-synthesis-draft.md: 7 ⚠️ tensions (d15 closure capture, p11 vs Q8, Q4 vs d22, Q8 vs zero-dep toolchain, Q7 mailbox vs d04, Q1, Q13 rationale), top ten steals, open questions grouped for one-at-a-time asking. Draft for Fable.
- plans/comparison-pass.md status: done. HANDOFF.md "Where we stopped" updated.

## [2026-09-12] ingest | Robert's research runs: Q17 defenses + landscape second lane
- research/concepts/supply-chain-defenses.md from raw/research-runs/supply-chain-defenses-survey.pplx.md and package-security-research-review.pplx.md (ledger [125], [126]). No recommendation; six design options for Q17. Q17 prompt 1 (incidents) still has no run.
- research/concepts/landscape-second-lane.md from emerging_languages_2022_2026.md, pl-ideas-that-did-not-win.pplx.md, llm-authored-programming-languages.pplx.md vs language-landscape.md. Shortlist not changed.

## [2026-09-12] ingest | Comparison: Motoko
- research/comparisons/motoko.md, follow-up from landscape-second-lane. Actors, commit points (trap reverts a message), await splits atomicity, stable-variable upgrade checks, Caffeine as the AI-authorship context.

## [2026-09-12] create | Concept: the case against new languages
- research/concepts/case-against-new-languages.md, follow-up from landscape-second-lane. Null hypothesis + what Mo would have to show; no verdict.

## [2026-09-12] create | Concept: capability module lineage
- research/concepts/capability-module-lineage.md, follow-up from landscape-second-lane. Newspeak's platform argument, Joe-E's tamed subset, Wyvern TSLs + non-transitive authority, Limbo load-time checks, the confused deputy; mapped to p13 / Q16 / Q17.

## [2026-09-12] update | Comparison refresh: agent-native cluster
- VeraBench numbers (grader conflict noted), ilo's self-reported failure, live star counts, Axis dormancy, from the agent-languages run and the VeraBench README.

## [2026-09-12] update | Comparison: MoonBit, FFT rebuttal
- Evidence gains Chris Allen's rebuttal of "faster than Rust" (corrected Rust 3.2–3.4× faster; unmerged baseline fixes) and the run's mimalloc note.

## [2026-09-12] ingest | Q17 incidents run into supply-chain-defenses
- raw/research-runs/supply-chain-incidents-2024-2026.pplx.md (ledger [151]). Section (b) rewritten: 20 of 47 incidents (ecosystem, date, reporters' category, reach, detection, mitigation, stopped/not stopped), category ranking by impact and trend, defenses with evidence. Gap note removed.
