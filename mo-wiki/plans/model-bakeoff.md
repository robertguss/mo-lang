---
title: "Model bake-off: Opus vs Grok vs Codex as workers"
created: 2026-09-12
updated: 2026-09-12
type: plan
tags: [roadmap, agents, meta]
sources: [plans/corpus.md]
status: in-progress
---

# Model bake-off: Opus vs Grok vs Codex as workers

Robert (session 5): Claude (Fable) stays in charge but is expensive, so its job is to delegate and review. Which worker model does the delegated work best? Same brief, same repo state, three models, scored by Fable against one rubric, and Robert picks.

## Round 1: the corpus

Task: [[corpus]], word for word. Every worker starts from branch `session-05` with an empty `examples/`.

| worker | where | branch |
|---|---|---|
| Claude Opus 5 | the main tree, Herdr pane `w3M:p2` | `session-05` (`examples/` there is the Opus entry) |
| Grok 4.6 | worktree `../mo-lang-grok`, pane `w3Q:p1` | `corpus-grok` |
| OpenAI Codex (gpt-6-astra) | worktree `../mo-lang-codex`, pane `w3R:p1` | `corpus-codex` |

Started: Opus at 19:34, Grok and Codex at 19:46 (12 Sep 2026). All three ran with approvals off and the identical prompt; only the branch name and the commit trailer differed.

## Rubric (scored by Fable, one row per worker)

1. **Completeness.** Files delivered of 50, `README.md` in reading order, `GAPS.md` present.
2. **Grammar adherence.** Count of constructs not in `grammar.md`. Invented syntax is the worst failure: the brief says never invent, record a gap instead.
3. **Law adherence.** Count of violations of chapters 2 and 3 in files that are supposed to compile: a `requires` without its `rejects`, a catch-all arm on a closed enum, a pure-body `for`, an unconsumed `Result`, a missing `within:`, an aliased `var`.
4. **Gap discipline.** Gaps recorded in `GAPS.md` versus gaps papered over. A worker that finds real holes in the grammar and names them scores higher than one that reports none.
5. **Taste.** Ruby-nice, 15–40 lines, one construct per file, plainest possible surrounding code. Robert's judgment, sampled on five files per worker.
6. **Process.** Wrote only inside `examples/`; committed every five files; pushed; stopped when done; no wiki edits.
7. **Cost.** Wall-clock from first to last commit, and tokens or dollars where the CLI reports them.

Scores land here as a table when all three finish. The winning `examples/` is merged into `session-05`; the others stay on their branches as evidence.

## Round 2 (proposed): the lexer

`toolchain/src/lexer.zig` against `grammar.md` §1, same three workers, judged by `zig build test` on the winning corpus plus `zig build bench` numbers. Objective, so it complements round 1's taste scoring.

## Related
- [[corpus]]
- [[roadmap]]
- [[session-05]]
- [[d01-agents-write-the-code]]
