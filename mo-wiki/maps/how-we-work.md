---
title: "How we work"
created: 2026-09-16
updated: 2026-09-16
type: map
tags: [process]
sources: [index.md, plans/roadmap.md, decisions/decision-log.md]
status: living
---

# How we work

The working agreements, the roles, the loop, and the instruments, for anyone (or any session) picking the project up.

- [[SCHEMA]] — the wiki's working agreements: page types, frontmatter, the decision log's columns, what a session records
- `.claude/skills/mo-lead/SKILL.md` in the repo — the lead's role and loop: brief, fresh worker, verify with probes the brief did not name, record, merge, report
- `HANDOFF.md` at the repo root — the state and the queue for the next session
- [[roadmap]] — the "Where we are" table and the done rows
- [[log]] — one entry per session, newest last
- [[decision-log]] — the decisions
- The sessions: [[session-01]], [[session-02]], [[session-03]], [[session-04]], [[session-05]], [[session-06]]

## The roles

The lead (a Fable session) writes briefs, verifies, decides, and records; it never writes code by hand. A worker (an Opus session in Herdr, one fresh session per step, medium effort) writes every line under `toolchain/` and `examples/`. Robert reviews the decision log. The rounds' agents are fresh sessions in their own worktrees, and the suites are written after the branching and never shown to them.

## The rules that were learned the hard way

Nothing is final until measured ([[d28-nothing-final-until-measured]]); every step ends in a numbers table, best of five, both runtimes. Zero new syntax where possible; a grammar change is Robert's call. The laws stay unless a round shows them costing loops without catching bugs. Worktrees are evidence and are never deleted or merged. A control run is pre-registered: predictions on the page before any session starts. The lead commits by path only. Verify with your own probes, on real inputs, with your own client: every finding that mattered came from an input no suite sent.

## The instruments

The suites live beside their plans under `mo-wiki/plans/*-suite/`; see [[the-rounds]] for the list. `mo-wiki/tools/lint.py` checks links, frontmatter, tags, orphans, and sizes. The site is built by Quartz from `site/` and published on every push to `main`.

## The research behind the design

- [[reading-pack-2026-09]] and [[research-summary-2026-09]] — the reading pack and the summary
- [[research/README]] — the surveys, author profiles, and standards pages
- `raw/` — every source as it was ingested, articles and research runs
