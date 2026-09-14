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

## [2026-09-13] session | Morning: step 12 accepted, merged; step 12b started
- Fable verified: suite green (kv in the corpus by discovery), kv keys survive a restart, 50k SETs → 19 MB resident, map-100k 47 ms, kv-10k-get 512 ms. Six decision rows. Merged to main. Step 12b (memoization out, never on every test) to a fresh session.

## [2026-09-13] session | Morning: step 12b accepted, merged; step 13 (C backend) started
- Fable verified: suite green, never-trips.mo trips without --sim, memo.zig gone, logstat-4k 80 ms. Two rows marked overturned, two added. Merged to main. C backend to a fresh session.

## [2026-09-13] session | Morning: control run round 2
- Mo 11.8 min, 0 loops to green, 791 lines, median 3 lines per function; Go 8.2; Python 7.9. All three verified. Branches control2-* kept as evidence, not merged. Two decision rows. Three round-2 sessions closed.

## [2026-09-13] session | Morning: step 13 (C backend) accepted, merged; step 14 started
- Fable verified: suite green, native logstat matches expected text and JSON, 200k lines 0.14 s / 37 MB, crash parity (same report, exit 70). Contracts-off default overturned on acceptance. Seven decision rows. Merged to main. Step 14 (follow-ups) to a fresh session. Roadmap rows updated.

## [2026-09-13] session | Late morning: step 14 accepted, merged; step 15 started
- Fable verified: suite green, a failing ensures reported by a native test binary, four stdlib rows present, build in usage. Two decision rows. Merged to main. Step 15 (processes and Net in C) to a fresh session.

## [2026-09-13] session | Afternoon: step 15 accepted, merged; step 16 started
- Fable verified: suite green (20.7 s), native kv over a real socket identical to `mo run` on malformed lines, a 70 KB line, a half line then close, and 20k SETs (native 12.5 MB resident, interpreter 27.3); two crashing programs of Fable's own (an invariant past its restart limit, a mailbox overflow from `main`) print the same report and exit 70 under both; a failing process test module identical as a test binary; aarch64 Linux static binary. Nine decision rows. Merged to main. Step 16 (HTTP in the stdlib) to a fresh session; round 3 of the control run after it.

## [2026-09-13] session | Afternoon: step 16 accepted, merged; control run round 3 started
- Fable verified: suite green (142 files, 21 s), httpd under `mo run` and native identical on fourteen curl and raw-socket cases (hello with an encoded query, a 404, HTTP/1.0, chunked → 501, a 2 MiB body → 413, garbage → 400, a header with no colon, HTTP/2.0 → 501, two content-lengths, a bad escape, a stalled client that does not block the next), servers under 5 MB after 300 more requests. Nine decision rows; one default flagged (prelude structs with omittable fields). Robert directed two stale-line fixes through the worker (parts E, F). Merged to main. Round 3 of the control run started in `../mo-lang-control3-*`. Lint: the three low-confidence rows and, new, `decision-log.md` over 200 lines; an append-only log grows by design, so the size rule should exempt it (a housekeeping item), and the row count is not trimmed.

## [2026-09-13] session | Afternoon: control run round 3 recorded; step 17 started
- Fable verified all three: Mo's four modules green, five runs against expected files, fmt clean, corpus test green in the worktree; Go check.sh, go test, go vet; Python check.sh and 69 tests. Wall-clock void for Mo and Go (the machine slept). Mo 9 loops (6 diagnostics), a real bug caught by a test and a never. Four decision rows, one locked (any(T) honours refinements). Branches control3-* kept as evidence. Three round-3 sessions closed. Step 17 (round 3 follow-ups) to a fresh session; program 4 spec next.

## [2026-09-13] session | Afternoon: step 17 accepted, merged; the outside review answered; step 18 started
- Fable verified: suite green (22 s), refined-type properties of Fable's own under both runtimes, MO0325 on an unsatisfiable where, a bad-byte file through read, read_lines, read_bytes under both runtimes, fold_lines, the six sentences tripped by hand. Three step rows. The outside review read and probed (recursion, closure capture, grouped patterns confirmed on today's binary); response page with baselines; Robert: laws and no-while stay, test and re-evaluate, document as baselines. Five review rows, two locked (Robert's call; the `semantic` tag). Merged to main. Step 18 (the review's no-compat fixes) to a fresh session; program 4 after it.
## [2026-09-13] session | Afternoon: outside review (Amp)
- Robert asked an outside agent for a full critique with the oracle and librarian. Two deep dives added: outside-review-2026-09-13 (verdict, ranked disagreements, keep/revise/drop, next five moves) and its evidence page (13 probes: unbounded recursion passes check, for-only loops give fictional bounds, invariant polarity, vacuous fault-injection asserts, handles not classified as capabilities, update-as-transaction not holding across ask/fs, durability never checks self-built witnesses, Roc platform precedent). Nothing merged or decided; pages marked contested for Robert to answer.

## [2026-09-13] session | Late afternoon: step 18 accepted, merged; the failure model; program 4 started
- Fable verified: suite green (22 s), eight probes of Fable's own under both runtimes (natural invariant, handle capture refused with MO0409 and MO0310, 50M-deep recursion as a Mo report with exit 70, grouped arm with a binding and a mismatch refused, map and set equality across orders, a body edit tripping MO0317, --until turning sim.mo to held). Ten decision rows, three locked, four tagged `semantic`. The failure model written into chapter 3. Merged to main. Program 4 (`notes`) to a fresh session.

## [2026-09-13] session | Evening: program 4 accepted, merged; step 19 started
- Fable verified: suite green (26 s), every notes module green under 100 seeds with faults, fmt clean, five run lines identical under both runtimes, a curl session of fourteen cases (401, cross-client 404, bad JSON, 405, 429 after 60, 413 on 2 MiB, 400 on a 62 KB field, title bounds, a control character), replay across restart, 20k notes at 48 MB. Seven decision rows, two tagged `semantic` (freeing finished processes; the held-send deadlock). Merged to main. Step 19 (what program 4 found, the dead each_line row, mutation tests) to a fresh session. Note: Robert's shell aliases `tr` to trash; Fable's probe hit it once, nothing was moved.

## [2026-09-13] session | Evening: session 6 ingestion (Perplexity Computer)
- Robert had Perplexity Computer sweep his Perplexity library for Mo-related research not yet in the vault. Six new files in `raw/research-runs/` (3 deep runs from sessions 4a4e7abb, 45e714aa, 256a997f answering the Mo parallel-tracks prompts + the 3 short briefs from session 2c696217). Three adjacent runs into `raw/articles/` as `pplx-*`. New prompts page `research/prompts/prompts-mo-parallel-tracks.md` pairs each brief with its deep run. Session page `sessions/session-06.md`. No decisions changed; the three deep runs are inputs for Fable, to become `empirical-validation-plan` and `ecosystem-strategy` concept pages and revisions to `research-summary-2026-09` and `case-against-new-languages` on the next pass.
## [2026-09-13] session | Evening: a correction to the record
- Fable wrote in earlier entries and in reports to Robert that Robert typed instructions into the worker pane (the README and stdlib-intro fixes after step 16, the README fix after round 3, "merge to main" lines). Robert: "it's definitely not me". The text was Claude Code's own prompt suggestion shown in the worker's input after each turn. The edits themselves were sound and stay; the attribution was wrong. HANDOFF corrected; the suggestion line is ignored from now on.

## [2026-09-13] session | Evening: step 19 accepted, merged; step 20 started
- Fable verified: suite green (31 s); the never-freed reproduction at 200,000 under both runtimes with memory; the worker-per-exchange program at 20,000 requests under both runtimes; mkdir then write under both; --clock twice identical; three diagnostics by hand; each_line gone from both tables; the recipe check with a missing signature (MO0326) and a changed type, after finding that a plain mo check ignores the # recipe: line and that a changed recipe stales the sidecar first; a probe found a process with no capability parameter cannot start another (MO0403 since step 18), flagged. Seven decision rows, three tagged semantic. Merged to main. Step 20 (the runtime owns the loop, plus the three findings) to a fresh session.

## [2026-09-13] session | Night: step 20 accepted, merged; round 4 started
- Fable verified: suite green (31 s); a server of Fable's own on serve and lines (an acceptor handing each Conn to a router by message, a slow worker with a mailbox of 4 taking a 2,000-line burst with no crash and the right count, an idle client closed at 1.5 s) under both runtimes; a capability in a struct field still refused; MO0327 and MO0326 through a plain check; a process starting its supervisor's child without a capability; no for reaching accept or read_line anywhere in examples; echo native identical; workers at 20,000 under both. Ten decision rows, four tagged semantic, one flagged (MO0327's strength). Fable tripped MO0101 three times writing probes, the same diagnostic round 3's worker tripped: the one-line arm with an assignment is the syntax models reach for. Merged to main. Round 4 of the control run started. Queued for Fable: the three session 6 deep runs into two concept pages; the Perplexity VM-first drafts once their pages arrive.
## [2026-09-13] ingest | Research agenda 2026-09: R1 papers, R3 authors, R6 manifestos (Perplexity Computer, branch research-2026-09-13-perplexity)
- Robert asked Perplexity Computer to inspect the repo and wiki and propose further research. Scope settled by one-question-at-a-time clarification: an agenda page plus execution of one run per theme, full wiki integration on a branch as a PR.
- Agenda page `research/prompts/prompts-research-agenda-2026-09` with six runs: R1 papers (LLM-facing), R2 papers (systems and PL), R3 authors (the elders), R4 authors (the moderns), R5 manifestos (philosophies and specification), R6 manifestos (safety and reliability). R2, R4, R5 hold ready-to-run prompts; not executed.
- Three raw runs under `raw/research-runs/` with sha256: `2026-09-13-papers-llm-facing.pplx.md` (102 papers, sub-questions A1–A6, B1–B5), `2026-09-13-authors-the-elders.pplx.md` (Thompson, Ritchie, Kernighan, Pike, Hoare, Dijkstra, Wirth, Armstrong), `2026-09-13-manifestos-safety-reliability.pplx.md` (9 standards, 9 reliability philosophies, 56 rules ranked for Mo).
- Twelve concept pages under `research/concepts/`, each with a "What Mo could take" table marking strengthens / contradicts / new / already-in-Mo. Every quote carries its URL; unreachable primaries recorded as n.a. rather than paraphrased (Thompson on xz, Armstrong's "The Mess We're In", BARR-C:2018, Wirth's compile-speed rule is secondary via Franz).
- Headline contradictions for Robert to weigh, not decisions: shape laws (JPL numbers are "should" in the clarity tier; complexity metrics do not predict LLM performance once length is controlled); the `while` ban (invariant synthesis is cheap; JPL, MISRA and Ravenscar annotate rather than prohibit non-terminating loops; Dijkstra against mechanical translation); restart is not storage (Armstrong R6); source-first trust vs Trusting Trust and xz; vacuous fault-injection answered by reachability obligations (FoundationDB TEST(), Antithesis sometimes).
- Nothing decided or merged. Lint run; pre-existing warnings only plus none new expected.

## [2026-09-13] session | Night: control run round 4 recorded; the laws re-evaluated
- Fable verified all three (Mo: four modules green, five run lines, fmt clean, corpus test green in the worktree; Go: check.sh, go test, go vet; Python: check.sh, unittest). Mo 16.1 min to Go's 9.3 and Python's 9.0, loops 5/1/0, no check caught a bug anywhere. Three decision rows, one semantic "for Robert": keep the laws, spend an ergonomics step on the grammar's one-line forms. Merged to main. Three round-4 sessions closed. Fable's reading of the six deep runs next.

## [2026-09-13] session | Night: the session 6 deep runs read
- Fable read the three deep runs (empirical validation, ecosystem depth, agent authoring) into `research/concepts/empirical-validation-plan.md` (the seven experiments against the control runs; round 5 pre-registered, tokens counted, baselines with checks; the feature ablation first) and `ecosystem-strategy.md` (Q11 answered against the day-one list; TLS and crypto the gating bricks; recipes as kits with the conformance check as the upgrade story), and dated addenda on the research summary and the case-against page. Remaining of Fable's own: the research agenda's twelve concept pages for contradictions; the VM-first drafts once their pages arrive.

## [2026-09-13] session | Night: the VM-first drafts filed
- Robert's outside Perplexity session drafted two deep dives and five directions (d36–d40) on a VM-first runtime and agent-native runtime features; Fable filed them from the zip Robert sent, fixed two claims against the tree (no `mo mcp` command exists; chapter 8 is the milestone chapter), verified the two open questions on the VM page (cooperative turns, a region per process), added a note to each deep dive with the build order d40, d37, d38, d39 and the rule that the MCP surface is a capability, indexed them, bumped the schema's direction range. Liked, not locked; no decision rows.

## [2026-09-13] session | Night: the runtime surface's on-off rule
- Robert took Fable's recommendation on direction 37's one design fork: the introspection surface is a capability, on under `mo run` and `mo test`, off in a built binary unless `main` holds it. One semantic row; d37 updated.

## [2026-09-13] session | Night: the research agenda answered
- Fable read the twelve concept pages of the research agenda merge and called each "contradicts Mo" item on `deep-dives/research-agenda-2026-09-response.md` (agree 8, disagree 6, test 3). Chapter 2's recursion line rewritten to the depth bound the toolchain enforces; chapter 3 names R6; `empirical-validation-plan` gains round 5's two columns; nine decision-log rows, two `semantic`. Measured: `mo build` reproducible (kv's C and binary identical across two independently built `mo`s); `mo` differs only in `LC_UUID` and its ad-hoc signature. Lint run at the commit.

## [2026-09-14] session | Night: step 21 accepted
- Step 21 (memory and green threads) accepted after `zig build test` green and Fable's probes under both runtimes: a process is a fiber, 65,530 idle connections held, a process at rest 38.8 / 22.7 KiB, socket rows faster, the four chapter 7 bets measured, `Fs.fixture()` refuses `..`, three diagnostics with a `mo fix`. One finding by probe (HTTP backpressure counts request-less connections, about 1,000) flagged for program 1; the Linux poller never ran. Eleven decision-log rows, five `semantic`. Merged to `main`. Lint: the same pre-existing 16 issues from Robert's history bundle (13 pages typed `research`, 3 broken links) plus six review rows.

## [2026-09-14] session | Night: program 1 accepted
- `jobq` accepted after the suite went green with it in the corpus and Fable's 29-check HTTP session passed under both runtimes (statuses, a lease running out, dead on the last attempt, a restart, a 40-worker race, a 1,200-connection crowd). Nine decision-log rows, four `semantic`, one for Robert (the `invariant` construct found no use). d37 gains the nine runtime-surface questions. Follow-up step 22 listed. Merged to `main`. Lint unchanged (the history bundle's 16, six review rows).

## [2026-09-14] session | Night: round 5, pre-registered, mixed
- Three fresh sessions in `../mo-lang-control5-*` from 01:14; Fable verified each in its worktree. P1 and P3 held, P2 missed by one loop. The laws stay; the `is` form's diagnostic to step 22; tokens to be read before the report next time. Four decision rows. Merged to `main`.

## [2026-09-14] session | Night: step 22 accepted
- The derived deadline (`Deadline`, `reply_by`, `at_most`) in both runtimes, verified by Fable's probes in all three modes; jobq's sums gone; the `--recipe` line count, the fixture's missing folder, `json.to_i64`, the recipe's rewrite rule with notes following it, two diagnostics. Five decision rows, two `semantic`. Merged to `main`. Next: the runtime surface step for d37–40.

## [2026-09-14] session | Night: step 23 accepted
- The runtime surface (directions 37 and 40) in both runtimes, verified by Fable's probes: every route under `mo run --surface` and as a `--surface` binary, pause and resume, `read_only`, a binary without the surface, a failed seed's events, jobq's sources and slowest updates. Five decision rows, two `semantic`. d37 and d40 carry a "Built" note. Merged to `main`. Next: program 5's spec.

## [2026-09-14] session | Night: program 5 accepted
- `agent` accepted after the suite went green and Fable's 22-check session passed under both runtimes. Nine decision rows, four `semantic`, one for Robert (the handle-in-state call, overturning part of step 18), the invariant row updated with program 5's two kept invariants. Step 24 listed. Merged to `main`.

## [2026-09-14] session | Morning: Robert's calls, and a rule from the worker
- Robert, awake: the one-line `if` as a value is in (pick 16), a keyword may name a field after a dot, the `invariant` construct waits for program 6, tools are installed without asking (agreement 10, `uv` for Python); mypy, ruff, and a staticcheck for Go 1.27 installed; the round 5 Python passes `mypy --strict`. The step 24 worker caught Fable's `git add -A` sweeping its in-progress edits into wiki commits; the handoff now says `git add <paths>` only.

## [2026-09-14] session | Morning: the loop becomes a skill
- Robert, leaving for work: the roles and the Herdr loop moved out of the handoff into a project skill, `.claude/skills/mo-lead/SKILL.md`, loaded by a new root `CLAUDE.md`; `HANDOFF.md` rewritten to hold only the state and the queue (accept step 24, step 25, round 6 with the baselines' checks bolted on, program 6). Step 24's worker was mid-part D when he left and commits its own parts.

## [2026-09-14] session | Morning: step 24 accepted
- The authority hole, a handle in a state field, the delayed send, `Deadline.remaining`, four gaps, and the simulator's ask, verified by Fable's probes under both runtimes (a registry of its own, a delayed send timed and dropped on a crash, the jobq and agent sessions again). Seven decision rows, five `semantic`; one default overturned in shape (agent's writable folder, to step 25). Merged to `main`. Step 25 starts.

## [2026-09-14] session | Morning: stopped
- Robert: no more steps, leaving for work. Step 25's worker, started seconds earlier, exited with no commits; the handoff, roadmap, and log say step 25 is next and not started. The loop ends here; the next session resumes from `HANDOFF.md` through the `mo-lead` skill.

## [2026-09-14] session | Day: the VM, and step 25 accepted
- The lead resumed on the exe.dev VM at 12:30 UTC: no Zig, no `mo`, no Mac pane; Zig 0.16 installed with `mise`, the worker in `w7:p7`. Part A had reached `origin/session-05` from the Mac at 08:04 EDT after the handoff said no commits; a fresh worker took parts B–E from it. The suite's first Linux run was 175 pass, 3 fail, 1 crash: part A's hand-written `verified:` line, a Json test reading a dead stack frame, and the `--surface` test's ports inside Linux's ephemeral range; the worker fixed them as part F, none the poller's. Step 25 accepted after 184 of 184 and Fable's probes under both runtimes; eight decision rows, two `semantic`, one for Robert (a one-line `if` in tail position, to step 26). Merged to `main`.

## [2026-09-14] session | Day: step 26 accepted, round 6 pre-registered
- The tail-position one-line `if` and the two keyword diagnostics, verified by Fable's probes under both runtimes, 185 of 185. Three decision rows. Round 6 written on `control-run-6.md` before any session: logstat and jobq, the baselines with their checks bolted on, four predictions, the null hypothesis as P3; mypy and staticcheck installed on the VM. Merged to `main`. Round 6 starts.

## [2026-09-14] session | Day: round 6, failed on all four predictions
- Three fresh sessions from 14:30 UTC in `../mo-lang-control6-*`, the baselines with their checks bolted on; Fable verified each worktree (Mo 185 of 185, Go and Python every check clean). P1 1.58, P2 one shape-law loop and five keyword or grammar loops, P3 no check caught a real bug anywhere so the null hypothesis stands, P4 0.74. Five decision rows, three for Robert (the laws, the `never` over a `var` copy, the keywords as names). No seventh round until one lands. Merged to `main`.

## [2026-09-14] session | Afternoon: Robert agrees, step 27 starts
- Robert agreed to all three round 6 recommendations. Chapter 2 gains "Session 6 changes": the file law dropped (not demoted, since the honesty laws forbid warnings), a `never` reads values at rest, `state`/`result`/`old` as names outside the reserved positions. Five locked rows. Step 27 written and started on a fresh worker.

## [2026-09-14] session | Afternoon: the control run's measure changes
- Robert: agent time to green was never the point and no model has seen Mo, so from round 7 the predictions are native speed and memory against Go and Python, the feedback loop's time, and the dependency count (a column round 6 lacked: Mo 0, Go 1, Python 3); agent time and loops recorded only. Chapter 8 gains a Session 6 paragraph; one locked row; the handoff's round 7 entry rewritten.

## [2026-09-14] session | Afternoon: reliability is the target
- Robert: reliability of agent-written Mo is what he optimizes for, agent time is not. Round 7's first prediction becomes a hidden adversarial defect suite for jobq, written by Fable before the round and run against all three programs. Later, when a program finishes with no new gap or bug note, Mo reimplements a real open-source tool against its own test suite (CommonMark or Raft). Two locked rows; the roadmap's program 7.

## [2026-09-14] session | Afternoon: step 27 accepted, round 7 starts
- The file law gone, the three words as names, the `never` at-rest rule, the escape, `fold_lines`, verified by Fable's probes under both runtimes, 185 of 185. Four decision rows, one `semantic`. Merged to `main`. Round 7 starts on the pre-registered page with the hidden defect suite.

## [2026-09-14] session | Afternoon: the outside review
- Robert's outside review of the vault after round 6, filed verbatim with Fable's response: already done (the file law, the keywords, the `never` rule, the reframed measure), wrong on facts (the C backend exists), agreed and queued (the counted laws as settings, the `try` wording, the zero-dependency cost, program 7's pick, a closure column, a scale benchmark), disagreed (a JSON `verified:` line, the Ruby framing). The fork, the runtime as the thesis, is Robert's question. Two decision rows, one for Robert.

## [2026-09-14] session | Afternoon: the thesis restated
- Robert said yes to the fork the outside review named: chapter 1 rewritten by Fable as three layers (the runtime, capabilities and recipes, the language as their surface), the counted laws as settings, the measure as reliability, speed, the loop, and dependencies, the null hypothesis section rewritten with rounds 1 to 6 as evidence. One locked row.

## [2026-09-14] session | Afternoon: the reviewer's reply
- The reviewer conceded the C backend and the corpus size, withdrew sigils and the JSON `verified:` line, and pushed on three things Fable took: the BEAM as chapter 1's null hypothesis, the one-sentence thesis, the closure counterfactual (an audit, not a second worker), the zero-dependency fallback (a brick wrapping a C library under audit), and a Redis-subset shortlist for program 7. One provisional row.
