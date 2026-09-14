---
title: "Program 1: jobq in Mo, brief for the worker"
created: 2026-09-14
updated: 2026-09-14
type: plan
tags: [agents, processes, runtime, roadmap]
sources: [spec/programs/01-job-queue.md, plans/program-4.md, plans/interpreter-step-21.md, decisions/decision-log.md]
status: done
---

# Program 1: `jobq` in Mo, brief for the worker

The founding premise's first real test, after every step it waited for: HTTP (16), a store recipe and recipe conformance (program 4, step 19), the runtime owning the loop (20), a process that is not a thread (21). Spec: `mo-wiki/spec/programs/01-job-queue.md`. Implement it in Mo under `examples/programs/jobq/` with only what the toolchain provides (`toolchain/PRELUDE.md`, `spec/design-v0/09-stdlib.md`). Same rules as [[program-4]]: `examples/` only; toolchain bugs go in `examples/programs/jobq/TOOLCHAIN-BUGS.md` with reproductions and are worked around, never fixed; language gaps in `examples/GAPS.md`; formatted; every `requires` has its `rejects`; the final message carries the spec's measurements and every open point you decided.

## Orientation

The spec; `examples/programs/notes/` (the shape to copy: api, service, store, server, main, `check`); `examples/recipes/store.mo` and `mo check --recipe`; `03-semantics.md` (the failure model: what restart loses, the held-send rule, what a message may carry); the `## Http` rows; `plans/interpreter-step-21.md` (a process is cheap now; the HTTP backpressure finding); the decision rows of 13–14 Sep night (the `within:` count, the Q16 ledger, invariants that must be trippable).

## Shape

`Jobq.Api` (routes, JSON, statuses), `Jobq.Queue` (a process per queue name: its jobs, the queued order, the leases, `invariant`s, `never`s), `Jobq.Registry` (the process that starts a `Queue` per name and routes to it; or one process for all queues if the worker judges that simpler, said in the report), `Jobq.Store` (the store recipe implemented over `Fs`, checked with `# recipe: Recipes.Store`), `Jobq.Server` (the acceptor the runtime serves into, a worker per exchange), `Jobq.Main` (`serve`, `compact`, `client`, `check`). A job's record is one JSON string in the store under its id. Lease expiry is lazy, as the spec says; if a real timer is needed, record it as a gap and keep the lazy rule.

## Tests and the check

As the spec lists, including the 1,200 request-less connections test over `Http.fixture()` or a real socket, the two-worker race, and the `--sim 100 --faults --until` run. The corpus test runs `jobq check` over a `data/` folder and a script as `notes check` does, plus `compact`, a usage error, a missing folder, and a client with no server; every `# run:` line identical under `mo run` and as a binary.

## Numbers

The spec's "Measured" table, both runtimes; the `within:` count with its two columns; loops to green by cause (a law, a grammar form, a diagnostic, a test mistake, a real bug); the Q16 ledger (a law that blocked the program, as opposed to a missing row: expected empty); each `invariant` left out as untrippable, with why; the runtime-surface questions; wall-clock.

## Done when

Corpus test green with `jobq` in `examples/programs/`, identical under `mo run` and as a binary, the real-socket check passes, `mo check --recipe` green on the store, the numbers, pushed, a numbered list "Decisions the brief did not cover".

## Result

Written in 40 minutes: nine modules, 195 functions, 2,891 lines with tests, `--sim 100` under faults with `--until`, `mo check --recipe` green on the store, the five run lines identical under both runtimes. Verified by Fable with an HTTP session of 29 checks under both runtimes, all green: every status the spec names, a lease running out and re-leased with `attempts` 2, a fail on the last attempt to `dead`, a restart keeping a dead job and re-leasing a run-out one, a 40-worker race with exactly one holder, 1,200 silent connections with a create answered at once.

| measure | `mo run` | binary |
|---|---|---|
| lease and ack pairs per second, 1 / 32 workers | 2,416 / 2,846 | 3,180 / 4,051 |
| a run-out lease handed out again | 0.25 ms | 0.14 ms |
| resident at 100k jobs | 392 MiB | 207 MiB |
| replay of a 1M-record log (209 MiB) | 30.4 s | 8.9 s |
| restart with 10,000 run-out leases, ready / first lease | 0.39 s / 3.09 s | 0.09 s / 0.83 s |

**What it found.** The `within:` count: 36 literals, 15 chosen, 3 derived by hand, and two of the three wrong before the worker's second pass; literals lie where deadlines nest, so a derived deadline is designed in the follow-up step. Every one of eight candidate `invariant`s was untrippable and left out; the process's contracts are its `requires`, `ensures`, and `never`s, a finding for Robert. The Q16 ledger is empty; the laws cost 8 of 17 loops and shaped `main`. One toolchain bug (`mo check --recipe` counts the recipe's tests against the 500-line law) and five gaps (`state` and `old` cannot name a field, JSON numbers decode only as floats, a capability cannot be returned, the fixture lists a missing folder as empty, no derived deadline, no timer). Nine runtime-surface questions filed on [[d37-runtime-mcp-surface|direction 37]]. All of it goes to the follow-up step and round 5.

## Related
- [[program-4]]
- [[interpreter-step-21]]
- [[program-menu]]
- [[research-agenda-2026-09-response]]
