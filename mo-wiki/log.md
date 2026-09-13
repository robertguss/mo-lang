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

## [2026-09-12] session | Session 2 closeout bookkeeping
- sessions/session-02.md and HANDOFF.md updated with the second half of the session (Q11–Q17, two-lane research, Herdr worker, syntheses). Next: the 7 tensions, one at a time.

## [2026-09-12] session | Session 3: tension 1 answered
- Closure capture: Robert in on Bosque's rule → directions/d31-effects-never-hide-in-a-value.md; Session 3 notes on d15, p11, comparison-synthesis-draft.

## [2026-09-12] session | Session 3: tension 2 answered
- Loops vs tier 3: Robert in on loops kept, no invariant syntax, small-model checking + honest verified: line. Notes on q08, p11, synthesis draft.

## [2026-09-12] session | Session 3: tensions 3–7 decided by Claude at Robert's request
- Robert: stop speculating, decide, then build and test. Notes on q04, q08, q07, q01, q13, synthesis draft. New directions/d32-proving-is-a-separate-tool.md, directions/d33-bounded-mailboxes.md (confidence: low, first-tested-by on each).

## [2026-09-12] session | Session 3: Q17 answered; aube reviewed
- Q17: Robert in on the six-layer package design (questions/q17 Session 3 answer). Robert asked for https://aube.sh to be reviewed → raw/articles/aube-security-docs-2026-09-12.md (ledger [152]), research/comparisons/aube.md; seven additions folded into the Q17 answer.

## [2026-09-12] session | Session 3: directions 34, 35 (recipes, ecosystem)
- Robert's first-principles reframe of packages → directions/d34-packages-are-recipes.md, directions/d35-mo-is-an-ecosystem.md. Notes on q17, q11 (DB driver is a brick), roadmap (design-v0 is a folder).

## [2026-09-12] create | spec/design-v0/ (eight chapters)
- 00-readme, 01-premise, 02-laws, 03-semantics, 04-syntax, 05-verification, 06-packages, 07-toolchain, 08-milestone. Draft; every session-3 bet listed with its first test in 08.

## [2026-09-12] session | Session 3 closeout bookkeeping
- sessions/session-03.md, HANDOFF.md (session 4 prompt), index. Lint: 112 pages, only the low-confidence review flags on d32/d33/d34.

## [2026-09-12] restructure | Vault moved to wiki/ (monorepo)
- Robert: keep docs/research cleanly separate from code; Obsidian syncs only the vault. Everything wiki moved under wiki/ (git mv, history kept). Root keeps README.md, HANDOFF.md, docs/, examples/, toolchain/ (later). SCHEMA layout, README, HANDOFF updated; .obsidian/workspace.json untracked.

## [2026-09-12] restructure | wiki/ renamed to mo-wiki/
- Robert: rename. git mv; SCHEMA, README, HANDOFF, .gitignore updated.

## [2026-09-12] create | docs/grammar.md
- v0 grammar in EBNF, 11 sections plus semantic rules; chapter 6 recipe example aligned to `test rejects`.

## [2026-09-12] restructure | docs/ moved into the vault as mo-wiki/spec/
- Robert: the spec must sync to his phone; `docs/` is a confusing name inside a wiki. git mv docs → mo-wiki/spec; references updated in README, HANDOFF, SCHEMA, wiki pages.

## [2026-09-12] session | Session 3 end: pub question pending, phone references removed
- Robert dislikes `pub`; expose-line recommendation pending → HANDOFF. Robert: phones are not a design criterion; spec and SCHEMA cleaned. Session page updated.

## [2026-09-12] session | Session 4: `pub` replaced by the `expose` line
- Robert in on Elm-style `expose a, b, C` under `module`; privacy by default, no marker on declarations. Applied to spec/design-v0 (02–07), spec/grammar.md, syntax/p14 as Session 4 notes.

## [2026-09-12] session | Session 4: `use A.B{X, Y}` drops the dot
- Robert: no dot before the import braces. Applied to design-v0/04, grammar.md, p14, full-example-q1-q7.

## [2026-09-12] session | Session 4: every `for` closes with `end`; loops vs combinators
- Robert: comprehension `for` looked whitespace-sensitive → `end` added (design-v0/04, grammar). In on keeping `for` + map/filter/reduce with a formatter rule (pure body → combinator). Notes on p11.

## [2026-09-12] session | Session 4 closeout: moving to the laptop
- sessions/session-04.md, HANDOFF.md (session 5 prompt), index. Lint: 113 pages, only the low-confidence flags on d32/d33/d34.

## [2026-09-12] session | Session 5: design-v0 review complete
- Robert reviewed chapters 1, 2, 3, 5, 6, 7, 8 with no edits ("good" each). Status line in design-v0/00-readme.md notes the review. Next: the corpus (roadmap step 4).

## [2026-09-12] session | Session 5: corpus worker, toolchain layout, bake-off
- plans/corpus.md written; Opus worker started in Herdr on it. Robert: work goes on a feature branch → session-05 (the two earlier session-5 commits stay on main).
- toolchain/ laid out in Zig 0.16: stubs per stage, mo CLI, corpus test, mo-bench, bench/rebuild.sh (first incremental rebuild 127 ms). `zig build test` green.
- Robert: compare Opus, Grok, and Codex as workers, Fable delegates and reviews → plans/model-bakeoff.md; Grok and Codex started on the same brief in worktrees on corpus-grok and corpus-codex.

## [2026-09-12] session | Session 5: build first; gaps decided; step 1 brief
- Robert: no taste review of the corpus now; build, measure, evaluate; Fable may decide alone. Fable chose Opus as the code worker (bake-off round 1: Opus 5/5 taste, Codex found three grammar bugs, Grok not competitive).
- Fable decided every corpus gap: grammar.md productions fixed in place, "Session 5 decisions" at its foot; chapters 2 (deadline law), 3 (platform selection, supervisor params), 4 (example + rules), 6 (recipe example) amended with Session 5 notes.
- plans/interpreter-step-1.md: Opus brings the corpus up to date, then lexer + parser, corpus test tightens, bench rows.

## [2026-09-12] session | Session 5: step 1 accepted, step 2 briefed
- Opus: corpus caught up, lexer, parser, corpus test tightened to .parse, bench rows (lex 107 µs, parse 97 µs over 50 files; rebuild 122 ms). Fable verified with bad inputs; accepted. Eight remaining gaps closed in grammar.md; decision-log rows added. plans/interpreter-step-2.md (tier-1 checker) written.

## [2026-09-12] session | Session 5: step 2 accepted, step 3 briefed
- Opus (fresh session): prelude, types, laws, caps, corpus test at .check, bench (check 251 µs over 50 files, rebuild 121 ms). Fable verified with the 12 rejects plus a type mismatch, a try across mismatched enums, an effect in a pure function, a non-exhaustive case, a clean nested-pattern file. Accepted. Opus's three defaults ruled on in the decision log. plans/interpreter-step-3.md written (VM, tier-2 contracts, test runner, verified line; processes deferred to step 4).

## [2026-09-12] session | Session 5: step 3 accepted, step 4 briefed
- Opus (fresh session): refund.mo in the corpus, bytecode, VM, tier-2 contracts, runner, mo test, corpus test at .run, bench (run 538 µs over 51 files, slowest refund.mo 204 µs). Fable verified with overflow, failing ensures, non-tripping rejects, refinement boundary, old/inout; all right, exit codes right. Accepted. Chapter 4 example gained the two rejects tests the compiler demanded. plans/interpreter-step-4.md (processes, supervisors, Mo.Sim scheduler) written.

## [2026-09-12] session | Session 5: step 4 accepted, milestone met
- Opus (fresh session): sim.zig, transactions, invariants, mailbox bounds, supervisors, crash reports, refund queue test, invariant-trips.mo (52 files), bench (run 579 µs). Fable verified: refund queue, pipeline, invariant trip, plus transaction rollback, supervisor give-up, mailbox overflow via a loop; all correct with full crash reports. Accepted. Chapter 4 fixed again (result keyword, false property, Done message); 08-milestone.md marks the milestone met; ten decision-log rows.

## [2026-09-12] session | Overnight: step 5 accepted, merged to main, step 6 started
- Opus (fresh session): FORMAT.md, fmt.zig, MO0501/MO0502, MO0319, corpus formatted. Fable verified: all 52 files pass --check, a messy file formats to the rules, MO0501 fires on a pure body and not on an accumulating one, tests green. Accepted; five decision rows. session-05 merged to main. Step 6 (main, Mo.Server) handed to a fresh session.

## [2026-09-13] session | Overnight: step 6 accepted, merged; program 2 and the control runs started
- Opus: main, Mo.Server, mo run, three programs. Fable verified: expected output and exit codes match, scope escape blocked, crash in main exits 70, no-main file gives MO0408. Accepted; nine decision rows. Merged to main. Program 2 (logstat in Mo) to a fresh mo-opus session; Go and Python control runs to fresh sessions in worktrees control-go and control-python.

## [2026-09-13] session | Overnight: first toolchain finding from program 2
- A `mo run` of a worker probe reached 21 GB in three minutes and Fable killed it. The worker was measuring `push` at 2k/4k/8k elements: value-semantic append copies the whole list, and the per-run arena never frees, so a loop that builds a list is quadratic in memory. Chapter 7's Perceus-style in-place reuse for a unique `var` is exactly the missing piece; until then, runtime step 7 must give `push` on a `var` in-place growth and free per iteration. Background waits were killed by the memory pressure; the scheduled wakeup is the only signal now.

## [2026-09-13] session | Overnight: program 2 and the control run done; step 7 briefed
- Mo logstat verified with the file law lifted (four modules, tests, text and JSON match); Go and Python verified with their check.sh and tests. Control branches merged into session-05. Result table on plans/control-run.md. Three toolchain bugs → plans/interpreter-step-7.md (use imports functions, program root, multi-file corpus programs, push in place, speed); nine gaps → plans/interpreter-step-8.md (the stdlib). Grammar: use production changed. Six decision rows. Merged to main.

## [2026-09-13] session | Overnight: step 7 accepted, merged; step 8 started
- Fable verified: 43 logstat tests from four files, text and JSON match, 200k pushes 0.15 s / 59 MB, 200k-line log 60 s in Debug at 440 MB bounded. Seven decision rows (memoization flagged "watch closely"). Merged to main. Step 8 (stdlib, plus ReleaseSafe default) to a fresh session.

## [2026-09-13] session | Overnight: step 8 accepted, merged; step 9 started
- Fable verified: tests green, logstat text matches on `logstat <dir>`, 200k lines 0.95 s / 38 MB on the ReleaseSafe binary, 118 stdlib rows, 8 gaps left. Seven decision rows. Merged to main. Step 9 (Mo.Sim seeds and fault injection) to a fresh session.

## [2026-09-13] session | Overnight: step 9 accepted, merged; step 10 started
- Fable verified: tests green, refund under 100 seeds with faults holds (`sim (100 runs)`), racy.mo passes plain and fails under sim with interleaving and replay line. Five decision rows. Merged to main. Step 10 (sidecar, mo fix, error catalog, README) to a fresh session.

## [2026-09-13] session | Overnight: step 10 accepted, merged; step 11 started
- Fable verified: tests green, hand-edited verified line caught by MO0317 against the sidecar, mo fix rewrites a push loop to concat(map), errors.md has 59 rows, README tour reads well. Five decision rows. Merged to main. Step 11 (Net, processes under mo run) to a fresh session.

## [2026-09-13] session | Overnight: step 11 accepted, merged; program 3 started
- Fable verified: tests green, echo over a real socket with three clients, echo-1k 56 ms, Net rows in 09-stdlib.md and PRELUDE.md, usage text lists fmt and fix. Seven decision rows. Merged to main. Program 3 (kv over TCP) to a fresh session from its spec.

## [2026-09-13] session | Morning: program 3 done, corpus red, step 12 started
- kv written (five modules, 38 tests, sim green, 15k GETs/s) but the corpus test hard-codes counts (bug 1) so `zig build test` is red on session-05; not merged. Six bugs and eight gaps → plans/interpreter-step-12.md (runtime under real programs); the C backend renumbered to step 13. Grammar: optional return type, negative literal patterns. Seven decision rows.
