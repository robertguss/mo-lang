---
title: "Model bake-off: Opus vs Grok vs Codex as workers"
created: 2026-09-12
updated: 2026-09-17
type: plan
tags: [roadmap, agents, meta]
sources: [plans/corpus.md]
status: done
---

# Model bake-off: Opus vs Grok vs Codex as workers

Robert (session 5): Claude (Fable) stays in charge but is expensive, so its job is to delegate and review. Which worker model does the delegated work best? Same brief, same repo state, three models, scored by Fable against one rubric, and Robert picks.

## Round 1: the corpus

Task: [[corpus]], word for word. Every worker starts from branch `session-05` with an empty `examples/`.

| worker | where | branch |
|---|---|---|
| Claude Opus 5 | the main tree, Herdr pane `w3M:p2` | `session-05` (`examples/` there is the Opus entry) |
| Grok 4.6 | worktree `../mo-lang-grok` (removed; the branch stays), pane `w3Q:p1` | `corpus-grok` |
| OpenAI Codex (gpt-6-astra) | worktree `../mo-lang-codex` (removed; the branch stays), pane `w3R:p1` | `corpus-codex` |

Started: Opus at 19:34, Grok and Codex at 19:46 (12 Sep 2026). All three ran with approvals off and the identical prompt; only the branch name and the commit trailer differed.

## Rubric (scored by Fable, one row per worker)

1. **Completeness.** Files delivered of 50, `README.md` in reading order, `GAPS.md` present.
2. **Grammar adherence.** Count of constructs not in `grammar.md`. Invented syntax is the worst failure: the brief says never invent, record a gap instead.
3. **Law adherence.** Count of violations of chapters 2 and 3 in files that are supposed to compile: a `requires` without its `rejects`, a catch-all arm on a closed enum, a pure-body `for`, an unconsumed `Result`, a missing `within:`, an aliased `var`.
4. **Gap discipline.** Gaps recorded in `GAPS.md` versus gaps papered over. A worker that finds real holes in the grammar and names them scores higher than one that reports none.
5. **Taste.** Ruby-nice, 15–40 lines, one construct per file, plainest possible surrounding code. Robert's judgment, sampled on five files per worker.
6. **Process.** Wrote only inside `examples/`; committed every five files; pushed; stopped when done; no wiki edits.
7. **Cost.** Wall-clock from first to last commit, and tokens or dollars where the CLI reports them.

## Round 1 scores (Fable, 12 Sep 2026, 19:55)

All three delivered 50 files, `README.md`, `GAPS.md`, and 12 `rejects/` files with an `# expect error:` line, in ten to thirteen commits, and touched nothing outside `examples/`. Scored 1–5 after reading the same twelve files from each worker plus every `GAPS.md`.

| criterion | Opus | Grok | Codex |
|---|---|---|---|
| Completeness | 5 | 5 | 5 |
| Grammar adherence | 4 | 3 | 4 |
| Law adherence | 4 | 3 | 5 |
| Gap discipline | 5 | 3 | 5 |
| Taste | 5 | 2 | 3 |
| Process | 5 | 5 | 5 |
| Wall-clock, first to last commit | 8 min | 6 min | 9 min |

- **Opus.** Real domains (an invoice, seat bookings, a session clock), intent lines that teach, tests that mean something, the cleanest `ask` reply form. 39 gaps, one decision per line, readable. Slips: one file at 46 lines (recorded), `assert x is Ok(start)` binds a name out of an assert (a scope gap Codex caught and Opus did not), `contains?` and `Duration` assumed.
- **Grok.** Fastest and shortest, but ten tautological asserts (`assert t == t`, `assert h == h`), nine tests named "never reached", `state.n = state.n` to fill an arm, a `rejects` test that trips no `requires`, `within:` passed to a plain function. 17 gaps; several holes it hit went unrecorded. Not competitive on this task.
- **Codex.** The most careful reader of the grammar: found that `cmp` demands a range after `is pattern`, that `assert` is missing from `stmt`, and that `old` is restricted to `ensures` while `invariant` needs it. Law-clean. But it dodges the construct under test (the clock file tests a budget number, the counter file tests a pure helper), runs declarations together with no blank lines, and its gap prose is dense.

**Result** (round 1 scored and decided; round 2 never ran and is dropped)**:** Opus's `examples/` is the base. Robert (session 5): Fable chooses the worker model for all building and writing from here; Fable chose **Opus**, on taste and gap discipline, with Codex-style grammar rigour supplied in Fable's review. Codex's grammar findings go into `grammar.md` as Session 5 fixes. Grok's branch stays as evidence.

## Round 2 (proposed): the lexer

`toolchain/src/lexer.zig` against `grammar.md` §1, same three workers, judged by `zig build test` on the winning corpus plus `zig build bench` numbers. Objective, so it complements round 1's taste scoring.

## Related
- [[corpus]]
- [[roadmap]]
- [[session-05]]
- [[d01-agents-write-the-code]]
