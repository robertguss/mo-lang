---
title: "Program 3: kv in Mo, brief for the worker"
created: 2026-09-13
updated: 2026-09-13
type: plan
tags: [agents, roadmap, performance]
sources: [spec/programs/03-kv-store.md]
status: done
---

# Program 3: `kv` in Mo, brief for the worker

The second real program. Spec: `mo-wiki/spec/programs/03-kv-store.md`. Implement it in Mo under `examples/programs/kv/` with only what the toolchain provides (`toolchain/PRELUDE.md`, `spec/design-v0/09-stdlib.md`). Same rules as [[program-2]]: `examples/` only; toolchain bugs go in `TOOLCHAIN-BUGS.md` with reproductions and are worked around, never fixed; language gaps go in `GAPS.md`; formatted; every `requires` has its `rejects`; the final message carries the spec's measurements and every open point you decided.

## Shape

`Kv.Protocol` (parse and render lines), `Kv.Store` (the process: state, messages, `update`, invariants, `never`s), `Kv.Log` (append, replay, compact over `Fs`), `Kv.Server` (listener process, one worker process per connection, the 64-client bound as a mailbox or a counter), `Kv.Main` (`serve`, `compact`, `client`). Tests as the spec lists; `--sim 100` must hold.

## Done when

Corpus test green with `kv` in `examples/programs/`, the real-socket program check passes, measurements in the final message, pushed.

## Result

Written in 40 minutes (60 with measurements): five modules, 93 functions, median 4 body lines, longest 16, 38 tests, `--sim 100` holds under faults. Verified by Fable: the corpus passes on a toolchain copy with the hard-coded counts updated (bug 1); the real `zig build test` is red until step 12 lands, so this is not merged to `main` yet. Real socket: 15,306 GETs/s with one client, 19,320 with 32; 10,081 and 11,265 SETs/s. Two spec requirements unmet because no stdlib row writes a file: durability across restart, and a 1M-line replay. Six toolchain bugs (`TOOLCHAIN-BUGS.md`) and eight gaps; all go to [[interpreter-step-12]].

## Related
- [[interpreter-step-11]]
- [[program-menu]]
