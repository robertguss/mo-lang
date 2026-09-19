---
title: "How we work"
created: 2026-09-16
updated: 2026-09-19
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
- [[roadmap]] — the board (now, next, waiting on Robert, recently done), the phase table, and the done rows
- [[log]] — one entry per session, newest last
- [[decision-log]] — the decisions
- The sessions: [[session-01]], [[session-02]], [[session-03]], [[session-04]], [[session-05]], [[session-06]]

## The roles

Robert's 19 Sep instructions keep Astra as lead in this Mac session, with fresh
Astra workers at low reasoning in Herdr panes. The oracle requirement and Amp
worker workflow are superseded. The lead writes briefs, verifies, decides and
records; workers own code under `toolchain/` and `examples/`. Robert reviews
the decision log. `mo-lead` holds the exact launch and acceptance procedure.

Implementation workers have separate worktrees and exact base/write scopes;
read-only reviews may share the lead checkout. The lead inspects returned
changes, preserves raw evidence and reruns acceptance in its own checkout. A
worker's green report is not acceptance. Preserve historical worktrees and keep
sealed suites away from workers. Robert's overnight authority authorizes lead
decisions and bounded setup/implementation while he is AFK; independent work
continues around prerequisites requiring his presence.

## The auditor (17 Sep 2026)

A separate reader Robert installed after the outside review of 17 Sep: a Perplexity session only he opens, which reads raw evidence and files `audit/mo-audit-<date>-<subject>.md` in the repo, never Fable's synthesis first. Three stopping rules are ratified there (the runtime claim and the capabilities claim on program 7, the language's catch claim at erosion generation ten). Fable's parallel readings, the evidence bundles under `audit/evidence/<date>/`, and where the two readings meet: [[the-audit-workflow]].

## The rules that were learned the hard way

Nothing is final until measured ([[d28-nothing-final-until-measured]]); every step ends in a numbers table, best of five, both runtimes. Zero new syntax where possible; a grammar change is Robert's call. The laws stay unless a round shows them costing loops without catching bugs. Worktrees are evidence and are never deleted or merged. A control run is pre-registered: predictions on the page before any session starts. The lead commits by path only. Verify with your own probes, on real inputs, with your own client: every finding that mattered came from an input no suite sent.

## The instruments

[[mo-executor-foundation]] is the accepted bounded fixture executor and protected
verdict path for [[mo-first-coding-harness]]. [[mo-agent-terminal-auth]],
[[mo-provider-foundation]], [[mo-coding-fixture-v1]], [[mo-workspace-foundation]]
and [[mo-provider-auth-v1]] have independent bounded acceptance. The next links
are [[mo-provider-bridge-v1]] for recorded native-history continuation and
[[mo-application-build-v1]] for the isolated pinned toolchain. Fixture acceptance
does not replace independent application acceptance or historical audit obligations.

The suites live beside their plans under `mo-wiki/plans/*-suite/`; see [[the-rounds]] for the list. `mo-wiki/tools/lint.py` checks links, frontmatter, tags, orphans, and sizes. The site is built by Quartz from `site/` and published on every push to `main`.

## The research behind the design

- [[reading-pack-2026-09]] and [[research-summary-2026-09]] — the reading pack and the summary
- [[research/README]] — the surveys, author profiles, and standards pages
- `raw/` — every source as it was ingested, articles and research runs
