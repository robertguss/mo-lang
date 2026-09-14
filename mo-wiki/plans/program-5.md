---
title: "Program 5: agent in Mo, brief for the worker"
created: 2026-09-14
updated: 2026-09-14
type: plan
tags: [agents, processes, runtime, effects]
sources: [spec/programs/05-agent-harness.md, plans/program-1.md, plans/interpreter-step-22.md, plans/interpreter-step-23.md, decisions/decision-log.md]
status: in-progress
---

# Program 5: `agent` in Mo, brief for the worker

The program the menu calls "is Mo good at the thing it is for?": an agent harness under permissions, budgets, and retries. Spec: `mo-wiki/spec/programs/05-agent-harness.md`. Implement it in Mo under `examples/programs/agent/` with only what the toolchain provides (`toolchain/PRELUDE.md`, `spec/design-v0/09-stdlib.md`, the `## Runtime` table from step 23, `Deadline` and `reply_by` from step 22). Same rules as [[program-1]]: `examples/` only; toolchain bugs go in `examples/programs/agent/TOOLCHAIN-BUGS.md` with reproductions and are worked around, never fixed; language gaps in `examples/GAPS.md`; formatted; every `requires` has its `rejects`; the final message carries the spec's measurements and every open point you decided.

## Orientation

The spec; `examples/programs/jobq/` (the shape to copy: api, service, store, server, main, `check`, and the `Journal` module that runs on `reply_by`); `examples/recipes/store.mo`, `rate-limiter.mo` (the recipe shape) and `mo check --recipe`; `examples/processes/deadline.mo` (`reply_by`, `at_most`); `examples/effects/runtime.mo` and `examples/programs/surface/` (the surface); `03-semantics.md` (the failure model, the runtime surface); the `## Http`, `## Runtime` rows; the decision rows of 14 Sep night (a recipe's waiting signatures take a `Deadline`; the `within:` count; invariants that must be trippable; the Q16 ledger).

## The recipe, first

Before the program: `examples/recipes/model-client.mo`, `Recipes.ModelClient` as the spec describes it, in the shape of `store.mo`, its waiting signature taking `by: Deadline`. Then implemented in the program's own module and checked with `# recipe:`.

## Shape

`Agent.Api` (routes, JSON, statuses), `Agent.Run` (a process per run: its budget's `Deadline`, the step loop driven by messages, `invariant`s, `never`s), `Agent.Registry` (starts a `Run` per request and routes to it, or one service process if simpler, said in the report), `Agent.Tools` (each tool over its narrowed capability), `Agent.Model` (the recipe implemented), `Agent.Mock` (the scripted model, an HTTP server of its own), `Agent.Transcript` (the append-only log per run), `Agent.Server` (the acceptor the runtime serves into, a worker per exchange), `Agent.Main` (`serve`, `mock`, `run`, `client`, `check`). A run's step loop is messages the run process sends itself, never a `for`; every model and tool call runs on the run's `Deadline` through `reply_by` or the deadline carried in the run's state.

## Tests and the check

As the spec lists. The corpus test runs `agent check` over a `data/` folder, a mock script, and a runs file as `jobq check` does, plus `mock` and `run` lines, a usage error, a missing folder, and a client with no server; every `# run:` line identical under `mo run` and as a binary.

## Numbers

The spec's "Measured" list, both runtimes; the `within:` count with its two columns and a reason for each chosen literal; the three surface questions with their routes; loops to green by cause; the Q16 ledger; each `invariant` left out with why; wall-clock from the start of the session.

## Done when

Corpus test green with `agent` in `examples/programs/`, identical under `mo run` and as a binary, the real-socket check passes, `mo check --recipe` green on the model client, the numbers, pushed, a numbered list "Decisions the brief did not cover".

## Related
- [[program-1]]
- [[interpreter-step-22]]
- [[interpreter-step-23]]
- [[program-menu]]
