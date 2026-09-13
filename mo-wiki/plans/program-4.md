---
title: "Program 4: notes in Mo, brief for the worker"
created: 2026-09-13
updated: 2026-09-13
type: plan
tags: [agents, roadmap, stdlib, security]
sources: [spec/programs/04-web-backend.md, plans/program-menu.md, directions/d34-packages-are-recipes.md]
status: proposed
---

# Program 4: `notes` in Mo, brief for the worker

The third real program and the first over HTTP. Spec: `mo-wiki/spec/programs/04-web-backend.md`. Implement it in Mo under `examples/programs/notes/` with only what the toolchain provides (`toolchain/PRELUDE.md`, `spec/design-v0/09-stdlib.md`, the `## Http` rows from step 16). Same rules as [[program-3]]: `examples/` only; toolchain bugs go in `TOOLCHAIN-BUGS.md` with reproductions and are worked around, never fixed; language gaps go in `GAPS.md`; formatted; every `requires` has its `rejects`; the final message carries the spec's measurements and every open point you decided.

## The package story, first

Before the program: `examples/recipes/store.mo`, the `Recipes.Store` recipe as the spec describes it, in the shape of `examples/recipes/rate-limiter.mo`. Then implement both recipes inside the program's modules and say in the final message what the recipe form cost and saved. If the toolchain has no way to check an implementation against a recipe, record that as the first gap; the tests in the recipe still run against the implementation by hand.

## Shape

`Notes.Api` (routes, JSON in and out, statuses), `Notes.Service` (the process: state, messages, `update`, invariants, `never`s), `Notes.Store` (the store recipe implemented over `Fs`), `Notes.Limits` (the rate limiter recipe implemented), `Notes.Server` (the acceptor and a worker per exchange), `Notes.Main` (`serve`, `compact`, `client`, `check`). Tests as the spec lists; `--sim 100` must hold under faults. The corpus test runs `notes check` over a `data/` folder and a script as `kv check` does, plus `compact`, a usage error, a missing folder, and a client with no server.

## Done when

Corpus test green with `notes` in `examples/programs/`, identical under `mo run` and as a `mo build` binary, the real-socket check passes, measurements in the final message, pushed.

## Related
- [[program-3]]
- [[interpreter-step-16]]
- [[interpreter-step-17]]
- [[d34-packages-are-recipes]]
- [[program-menu]]
