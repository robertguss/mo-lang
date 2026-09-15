---
title: "Program 6: ledger in Mo, brief for the worker"
created: 2026-09-14
updated: 2026-09-14
type: plan
tags: [agents, processes, contracts, roadmap]
sources: [spec/programs/06-ledger.md, plans/program-1.md, plans/control-run-7.md, decisions/decision-log.md]
status: done
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

## Result

Accepted 15 Sep 2026, 01:50 UTC. Written in 92 minutes (23:52 to 01:24 UTC), 14 modules (money, entry, records, index, book, settle, teller, desk, store, journal, api, server, check, main), 315 functions, 4,430 lines; every module under `mo test`, the journal and server under 100 seeds with faults; `mo check --recipe` green on the store; the five run lines identical under both runtimes; the corpus test green on the first run. Fable's 35-check HTTP session green under `mo run` and as a binary, the kill under load and replay included.

| measure | `mo run` | binary |
|---|---|---|
| transfers a second, 1 / 32 clients | 476 / 496 | 654 / 1,168 |
| calls a batch under load | 1.33 | 1.46 |
| resident memory at 100k entries | 364 MB | 198 MB |
| replay 100k entries (66 MB log) | 156 s, peak 495 MB | 12.4 s, peak 198 MB |
| replay 500k | not run | 126 s, peak 1.38 GB |
| replay 1M | past the 10-minute opening deadline | killed at 4.2 GB |

`within:` count: 20 chosen and 7 derived outside tests (every file call the journal makes runs on what remains of its asker's deadline), 47 chosen in tests. Invariants: four kept, three tripped by a `test rejects` over a torn or doubled log, the fourth (every live hold has a future expiry or a pending `Expire`) untrippable in the finished code and kept anyway, against the spec's rule. The planted bug is caught by the `never` "money is created or destroyed" and by the first invariant on open. Loops to green 22: 6 grammar forms (`return` in a `case` arm three times, a qualified call twice, a split lambda body), 5 laws (a fixture in a helper twice, stale `verified:` lines, a 70-line `update`, a `for` around `accept`), 6 test mistakes, 1 type mistake, 3 real bugs, 1 toolchain. Strictly, no check caught a real bug the tests would not have; the batching bug was caught only by the load run. Toolchain bugs: a `restart: :never` process restarts after a crash; `platform.exit` waits on a pending delayed send. Gap: simulated time jumps to the next delayed send at every statement boundary. The Q16 ledger stays empty.

## Related
- [[interpreter-step-29]]
- [[program-1]]
- [[interpreter-step-28]]
- [[control-run-7]]
- [[decision-log]]
