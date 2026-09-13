---
title: "Step 10: the verified sidecar, mo fix, the error catalog, the README, brief for the worker"
created: 2026-09-13
updated: 2026-09-13
type: plan
tags: [tooling, verification, compiler]
sources: [spec/design-v0/05-verification.md, spec/design-v0/07-toolchain.md]
status: in-progress
---

# Step 10: the `verified:` sidecar, `mo fix`, the error catalog, the README

Four tooling items chapter 5 and 7 promise, each small.

## Write scope

`toolchain/`, `examples/`, `README.md` at the repo root, and one generated file `mo-wiki/spec/errors.md`. Branch `session-05`, one commit per part, push after every commit.

## Part A: the `verified:` line lives in the file

`mo test --write file.mo` writes (or replaces) the `verified:` line at the bottom of the file and records its hash, keyed by the file's declaration hashes, in `.mo.ids` beside the program root (JSON, toolchain-owned; create the sidecar design here: one entry per declaration with a stable id, the declaration's content hash, and the file's `verified:` hash). `MO0317` now fires only when the line in the file differs from the sidecar's record or the declarations changed since. Run `--write` over the corpus and commit the lines.

## Part B: `mo fix`

`mo fix file.mo` applies every diagnostic fix that carries confidence 100 and rewrites the file; `--dry-run` shows the diff. Give three codes such fixes: `MO0501` (pure `for` → `map`/`filter`/`reduce`, the three shapes the rule recognizes), `MO0307` unused binding (delete the line when its expression is pure), `MO0312` default parameter (drop the default and add the argument at every call in the file). Every other code gets an explicit `fixes: []`.

## Part C: the error catalog

Generate `mo-wiki/spec/errors.md` from the diagnostic tables in the source: one row per code with category, the `what` template, the `why`, and whether `mo fix` handles it. `zig build errors` regenerates it; the corpus test fails if the file is stale. This is chapter 5's "where Mo's philosophy is taught to a model that has never seen it".

## Part D: the README front door

Rewrite the repo root `README.md`: what Mo is in three sentences, the one-minute tour (a 15-line program), how to build and run (`zig build`, `mo run`, `mo test`, `mo fmt`), where the spec is, where the corpus is, the numbers table from the bench, and the process (briefs, workers, decision log). No marketing.

## Done when

All four parts in, corpus test green, pushed, decisions listed.

## Related
- [[interpreter-step-9]]
- [[d19-negative-space-is-the-contract]]
- [[decision-log]]
