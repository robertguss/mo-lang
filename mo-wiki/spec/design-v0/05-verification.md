# 5. Verification

## Three tiers

1. **Instant, blocking (target under 50 ms incremental).** Types, exhaustiveness, capabilities, `flows`, laws, contract presence, test presence. The compile loop.
2. **Fast, blocking (target under 100 ms per changed function).** Contracts and invariants checked at runtime while running the module's own tests and `rejects` tests.
3. **Slow, background, cached by hash.** Property tests under many seeds and simulation with fault injection, run by the interpreter. Results upgrade the `verified:` line when they land. An agent never waits on tier 3 to see whether its code compiles. A merge into a supervised deployment requires tier 3 green.

Static proving is **not** in the v0 toolchain. It lives in `mo prove`, a separate optional binary that vendors a pinned, statically linked solver and is never in a user program's build path. Until it exists, an unproven `ensures` shows honestly as tested, not proven.

## Loops and integers under tier 3

- Loops have no invariant syntax. Tier 3 does small-model checking (bounded unrolling, counterexample search) and simple invariant inference. What it can't prove stays "tested." An `invariant` line inside loops is a later add-on only if measurement shows agents need it.
- Bodies use sized integers with crash-on-overflow. Contracts use unbounded integers. Two obligations are reported separately: "ensures proven" and "no overflow proven (k of n)."

## The `verified:` line

Computed by the toolchain, in the file, at the bottom, part of a module's exposed interface. Fixed vocabulary:

```
verified: types, contracts, tests (3), property (200 seeds), sim (1_000 runs)
          proven: not run
```

The headline is the weakest obligation, so a human can watch it climb. Editing it by hand is a compile error.

## Failure is a work queue

A tier-3 failure on merged code is a bug, not a flag. A failed property is a found counterexample with seed and log; the agent takes it as a fix task. A crash in production is the same object. Nothing is filed for a human unless the fix changes an exposed signature, a contract, or a `never`.

Two guards against gaming: a change that edits a contract or test while its proof or test is failing is rejected; and when an agent changes a body, the `test` and `ensures` blocks of that declaration stay untouched in the same change.

## Diagnostics teach

Every diagnostic is a structured record: stable `code` (`MO0412`), `category`, `location` (declaration ID and line), `what`, `why`, zero or more machine-applicable `fix` candidates each with a confidence. Rendered as Elm-style prose for humans and JSON for agents. The `why` text is written once per code in the error catalog, which is where Mo's philosophy is taught to a model that has never seen it. Tier-3 counterexamples arrive the same way, never as raw prover output.
