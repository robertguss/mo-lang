---
title: "Step 18: the outside review's no-compat fixes, brief for the worker"
created: 2026-09-13
updated: 2026-09-13
type: plan
tags: [compiler, contracts, processes, laws, tooling]
sources: [deep-dives/outside-review-2026-09-13.md, deep-dives/outside-review-2026-09-13-evidence.md, deep-dives/outside-review-2026-09-13-response.md, decisions/decision-log.md]
status: done
---

# Step 18: the outside review's no-compat fixes

An outside review ([[outside-review-2026-09-13]], evidence on [[outside-review-2026-09-13-evidence]]) found holes that cost nothing to fix today and would cost a migration later. Fable's calls are on [[outside-review-2026-09-13-response]]. This step makes the fixes; nothing here changes a law.

## Orientation

The two review pages and the response, `spec/grammar.md` (`invariant`, `pattern`, `arm`), `spec/design-v0/03-semantics.md`, `04-syntax.md`, `05-verification.md`, `toolchain/src/caps.zig`, `check.zig`, `contracts.zig`, `sim.zig`, `ids.zig`, `runner.zig`, `vm.zig`, `runtime/mo_rt.c`, `examples/processes/`, `examples/programs/kv/`.

## Write scope

`toolchain/`, `examples/`, and these spec lines only: the `invariant` rule in `grammar.md`, `03-semantics.md`, and `04-syntax.md`; the `pattern` production in `grammar.md`; the equality sentence for maps and sets in `09-stdlib.md`; each edited section gets a "Session 5, step 18" line saying what changed. Branch `session-05`, one commit per part, push after every commit.

## Part A: `invariant` stays true

An `invariant` body is the condition that holds after every `update`, as the word has always meant; it trips when the body is false. `never` keeps the negative form. Rewrite every `invariant` in the corpus and the programs (chapter 4's `done never goes backwards` becomes `state.done >= old(state.done)`), the spec lines, and the crash report wording. Both runtimes. `processes/invariant-trips.mo` still trips.

## Part B: handles are authority, capture is refused

`Handle(T)` counts as a capability in `caps.zig`: a function that holds one is effectful, `flows` sees it, and the "no capability parameter means pure" rule is true again. An anonymous function that captures a capability or a handle is refused with a new `MO04xx` diagnostic saying to pass it as a parameter; a `rejects/` file proves it. A discarded value from a pure call (`xs.map(...)` on its own line) is refused as an unconsumed value, extending `MO0222`'s rule; the corpus and programs get fixed where they do it.

## Part C: a stack overflow is a Mo crash report

Recursion past a depth limit (choose it; record it) crashes with a report naming the function and the depth, as any other crash, exit code as a crash, in both runtimes; `mo run` never prints a Zig trace. A corpus test under `rejects/`-style expectations or a `test rejects` proves it.

## Part D: grouped patterns and equality

`A | B | C: body` in `arm`, each alternative a full pattern binding the same names or none; the grammar line, the formatter, the checker's exhaustiveness, both runtimes; `kv/log.mo`'s six identical arms become one. Maps and sets compare by content, not insertion order, in both runtimes and the spec sentence; a stdlib test proves it.

## Part E: the cache key and faults that stop

The `.mo.ids` sidecar's hash for a test result covers the transitive bodies the test reaches, not only contract hashes, so a callee body change invalidates the caller's `verified:` line; a corpus test edits a callee and expects `MO0317`. `mo test --faults P --until F` stops injecting after fraction `F` of the run, so a test can assert safety throughout and progress after faults stop; the usage text and `examples/effects/sim.mo` show it.

## Done when

Green, every corpus `invariant` rewritten and `invariant-trips.mo` still tripping, the `rejects/` file for capture, no Zig trace on recursion, one arm in `kv/log.mo`, equality by content, the cache-key test, `--until`, pushed, decisions listed.

## Related
- [[outside-review-2026-09-13-response]]
- [[interpreter-step-17]]
- [[program-4]]
