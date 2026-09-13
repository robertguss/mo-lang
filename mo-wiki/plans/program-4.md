---
title: "Program 4: notes in Mo, brief for the worker"
created: 2026-09-13
updated: 2026-09-13
type: plan
tags: [agents, roadmap, stdlib, security]
sources: [spec/programs/04-web-backend.md, plans/program-menu.md, directions/d34-packages-are-recipes.md]
status: done
---

# Program 4: `notes` in Mo, brief for the worker

The third real program and the first over HTTP. Spec: `mo-wiki/spec/programs/04-web-backend.md`. Implement it in Mo under `examples/programs/notes/` with only what the toolchain provides (`toolchain/PRELUDE.md`, `spec/design-v0/09-stdlib.md`, the `## Http` rows from step 16). Same rules as [[program-3]]: `examples/` only; toolchain bugs go in `TOOLCHAIN-BUGS.md` with reproductions and are worked around, never fixed; language gaps go in `GAPS.md`; formatted; every `requires` has its `rejects`; the final message carries the spec's measurements and every open point you decided.

## The package story, first

Before the program: `examples/recipes/store.mo`, the `Recipes.Store` recipe as the spec describes it, in the shape of `examples/recipes/rate-limiter.mo`. Then implement both recipes inside the program's modules and say in the final message what the recipe form cost and saved. If the toolchain has no way to check an implementation against a recipe, record that as the first gap; the tests in the recipe still run against the implementation by hand.

## Shape

`Notes.Api` (routes, JSON in and out, statuses), `Notes.Service` (the process: state, messages, `update`, invariants, `never`s), `Notes.Store` (the store recipe implemented over `Fs`), `Notes.Limits` (the rate limiter recipe implemented), `Notes.Server` (the acceptor and a worker per exchange), `Notes.Main` (`serve`, `compact`, `client`, `check`). Tests as the spec lists; `--sim 100` must hold under faults. The corpus test runs `notes check` over a `data/` folder and a script as `kv check` does, plus `compact`, a usage error, a missing folder, and a client with no server.

## Done when

Corpus test green with `notes` in `examples/programs/`, identical under `mo run` and as a `mo build` binary, the real-socket check passes, measurements in the final message, pushed.

## Result

Written in 55 minutes including 8 of measuring: eight modules, 136 functions, median 4 body lines, longest 22, 2,224 lines with tests, `--sim 100` holds under faults in every module. Verified by Fable: suite green with notes in the corpus (26 s), every module green under 100 seeds with faults, `mo fmt` clean, the five run lines identical under `mo run` and as a binary, a curl session of Fable's own (create, list with a prefix, get, update, delete, 401 without a token, 404 across clients, 400 on bad JSON and a missing field, 405 with an allow header, 429 after the sixtieth request, 413 on a 2 MiB body, 400 on a 62 KB body field, a 201-byte title, and a control character), a note surviving a restart, 20k notes at 48 MB resident interpreted.

| measure | `mo run` | binary |
|---|---|---|
| create, 1 client / 32 clients | 5,067/s / 5,050/s | 7,621/s / 10,468/s |
| get, 1 client / 32 clients | 7,324/s / 8,248/s | 11,819/s / 23,692/s |
| resident at 100k notes | 169 MiB | 103 MiB |
| replay of a 1M-line log (181 MB) | 21.1 s | 6.3 s |

**The package story.** The rate limiter recipe cost nothing and saved a design: 55 lines, green on the first run. Writing the store recipe first, about five minutes, settled the signatures, the error enum, both `never`s, and seven tests before any code, and its implementation then failed only on syntax. The costs: nothing in the toolchain links an implementation to its recipe, so both recipes' tests were copied by hand and can drift; a `recipe` block cannot hold a `never`; and the recipe's shape leaks into the runtime (every store call takes `Fs`, `allow?` returns a new limiter per request, which is the suspected cause of throughput falling round over round). Two loops to green of fifteen were the recipes'.

**What it found.** Two runtime findings that matter beyond this program. A started process is never freed: each keeps a thread and about 30 KiB after its last message, so the brief's shape, a worker per exchange, runs out of memory near 20,000 requests, and the worker answered each exchange in the acceptor instead. And an `update` that starts a worker and waits on it deadlocks silently, because sends are held until the update ends; the runtime does what chapter 3 says and nothing flags it. Seven gaps: no recipe conformance check, no `never` in a recipe, no way to hand a capability in a message, no `Fs` row that makes a folder, no fixed clock under `mo run`, `or` on a `Result`, and the acceptor's fictional bound again. Loops to green: 15, six of them in the service and five in the server, none in the three pure modules. All of it goes to [[interpreter-step-19]].

## Related
- [[program-3]]
- [[interpreter-step-16]]
- [[interpreter-step-17]]
- [[d34-packages-are-recipes]]
- [[program-menu]]
