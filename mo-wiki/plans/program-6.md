---
title: "Program 6: ledger in Mo, brief for the worker"
created: 2026-09-14
updated: 2026-09-14
type: plan
tags: [agents, processes, contracts, roadmap]
sources: [spec/programs/06-ledger.md, plans/program-1.md, plans/control-run-7.md, decisions/decision-log.md]
status: queued
---

# Program 6: `ledger` in Mo, brief for the worker

The program whose invariants are the point. Spec: `mo-wiki/spec/programs/06-ledger.md`, read twice. It runs after [[interpreter-step-28]], so the map in place, `Option.map`, `seconds`, a fixture clock that moves, and `Fs.list` kinds are there.

## Orientation

The spec; `examples/programs/jobq/` (the shape to copy: api, queue, store, server, main, `check`, the group-commit batch); `examples/recipes/store.mo` and `mo check --recipe`; `03-semantics.md` (the failure model, `delay:` on `send`, `reply_by`); `04-syntax.md` (`invariant`, `never`, `ensures`); `examples/processes/` for `delay:` and a registry; the decision rows on `invariant` from programs 1 and 5.

## Write scope

`examples/` only. A toolchain bug goes in `examples/programs/ledger/TOOLCHAIN-BUGS.md` with a reproduction and a workaround; a missing stdlib row in `examples/GAPS.md`. Branch `session-05`, commit after each module, push after every commit.

## Shape

`Ledger.Money` (the type, amounts, currencies), `Ledger.Entry` (accounts, entries, postings, their JSON), `Ledger.Book` (the pure rules: what a transfer, hold, capture, release, refund, settlement does to a book, with the `never`s over history), `Ledger.Store` (the recipe over `Fs`), `Ledger.Journal` (the process that owns the book: one batch per flush as jobq's queue, the `invariant`s, the delayed `Expire`, idempotency), `Ledger.Api`, `Ledger.Server`, `Ledger.Main`.

## Tests and the check

As the spec lists, the planted-bug test included. The corpus test runs `ledger check` over a `data/` folder and a script, plus `compact`, a usage error, a missing folder, and a client with no server; every `# run:` line identical under `mo run` and as a binary.

## Numbers

The spec's "Measured" table, both runtimes; the `within:` count with its two columns; for each `invariant` kept, the message that trips it, and for each left out, why; whether any check caught a real bug the tests would not have, said strictly; loops to green by cause; wall-clock; the Q16 ledger.

## Done when

Corpus test green with `ledger` in `examples/programs/`, identical under both runtimes, the real-socket check passes, `mo check --recipe` green on the store, the numbers, pushed, a numbered list "Decisions the brief did not cover".

## Related
- [[program-1]]
- [[interpreter-step-28]]
- [[control-run-7]]
- [[decision-log]]
