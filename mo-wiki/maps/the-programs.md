---
title: "The programs"
created: 2026-09-16
updated: 2026-09-16
type: map
tags: [programs, corpus]
status: living
---

# The programs

Six real programs, each written by a fresh Opus session from a spec the lead wrote, each finding two to four toolchain bugs and several gaps, each followed by a step that closed them. They are the corpus the rounds and the measurements run on.

| program | spec | plan | lines | what it is, and what it found |
|---|---|---|---|---|
| 1, jobq | [[01-job-queue]] | [[program-1]] | 3,057 | a durable lease-based job queue over HTTP on the store recipe; found that hand-written deadlines lie, and that `invariant` kept none of eight candidates; the round 7 to 10 program |
| 2, logstat | [[02-log-analyzer]] | [[program-2]] | 769 | a log analyzer; the first program, written in 25 minutes; the round 1 to 6 program and the stronger form of measurement 1 |
| 3, kv | [[03-kv-store]] | [[program-3]] | 1,619 | a TCP key-value store with a line protocol; found six runtime bugs (step 12) and became durable |
| 4, notes | [[04-web-backend]] | [[program-4]] | 2,160 | a notes service over HTTP, the first built from two recipes; found that a started process was never freed and that nothing checked an implementation against its recipe (step 19) |
| 5, agent | [[05-agent-harness]] | [[program-5]] | 4,551 | an agent harness with permissions, budgets, retries, and a scripted mock model; found an authority hole and asked for the delayed send (step 24) |
| 6, ledger | [[06-ledger]] | [[program-6]] | 4,450 | a double-entry payments ledger with holds, captures, settlement, idempotency, seven `never`s and four invariants; found `restart: :never` restarting anyway and replay memory unbounded (steps 29 and 29b) |

## The changes to program 1

- [[01b-job-queue-change]] — change 1: scheduled jobs, backoff, retry, the `tries` rename; the maintenance round ([[control-run-8]]), the small-model round ([[control-run-9]]), the Elixir round ([[control-run-10]])
- [[01c-job-queue-change-2]] — change 2: the folder checked at open, `503` and the service still answering, `/queues`, `verify`; generation two of the [[erosion-round]]

## The corpus and the menu

- [[corpus]] — the 50 single-construct files and the `rejects/`
- [[program-menu]] — the programs that were considered, and program 7 (a Redis subset against Redis's own tests), the one chapter 1 says answers the BEAM
- [[q14-first-real-program]]
- [[bodies-as-cache]] — every program regenerated from its stripped spec, twice, all at 1.0
- [[model-bakeoff]] — the same corpus brief by three models
