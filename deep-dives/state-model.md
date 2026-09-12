---
title: "State model"
created: 2026-09-12
updated: 2026-09-12
type: deep-dive
tags: [state, processes]
sources: [raw/notion/design-journal-2026-09-12.md]
---

# State model

### Why state hurts, precisely
Not mutation itself. Three things OOP maximized:
1. **Aliasing plus mutation.** Two names for one memory, one changes it.
2. **Hidden state.** A call changes something invisible from the call site; the signature lies.
3. **Time.** "What is x" has no answer without "when."
For an agent reasoning over a context window, each one means "you must read code that isn't in front of you."
### Options weighed
| Option | Pros | Cons |
|---|---|---|
| 1. Shared mutable (imperative default) | Fast to write, matches machine | All three pains. Off the table. |
| 2. Pure functional, explicit threading (State monad, Elixir passing) | Total honesty, trivially testable | Monad ceremony, awkward accumulators, humans reject it |
| 3. Mutable value semantics (Swift, Hylo) | Natural loops, C-level perf, no borrow checker; no aliasing so pains 1 and 3 vanish | Needs a story for large shared structures; less familiar to models |
| 4. Ownership + borrowing (Rust) | Strongest guarantees, full expressiveness | Lifetimes: the #1 failure for humans and agents. Too expensive given option 3 |
| 5. State only in actors (Erlang, Elm) | Time explicit as message sequence, replay free, isolation free, supervision | Shared things become round-trips; god-process blobs; giant update fns |
| 6. Value/identity split (Clojure atoms, refs, STM) | Philosophically right | STM hard natively; reintroduces shared mutable identity |
| 7. State as algebraic effect (Koka) | Signature tells the truth; swap handler for test/replay | Unfamiliar, can get abstract |
| 8. Event sourcing (state = fold over log) | Log is truth; replay/audit built in; perfect for agent repro | Log growth, snapshots, schema evolution; overkill for a counter |
| 9. Relational / Datalog (Eve, Rel) | Very verifiable | Too far from what models know. Shelved |
### Claude's proposed synthesis (stack 3 + 5 + 7 + 8, one concept per layer)
- **Values are immutable with value semantics.** Inside a function, `var` allows in-place mutation because the compiler guarantees no aliasing. Semantically a chain of rebinding that reaches inside a value (Elixir's `x = x + 1`, one step further).
- **Identity exists in exactly one place: a process.** Anything that changes over time and outlives a call is a process, changed only via pure `update`. No globals, statics, refs, or atoms.
- **State access is visible in the signature** as an effect (Koka). Unifies with capabilities: the effect declaration is also the permission.
- **Process state types carry invariants checked at every transition.** Tiger Style paired assertions promoted into the language; provable in verified mode.
- **Every process is replayable from snapshot + message log.** Event sourcing as a runtime property. Persistence is a platform decision; semantics always present.
**Costs, stated plainly:** shared caches/pools/config live in a process or a platform capability (a round-trip where Go uses a mutex); big process states need nested state machines (function length law forces decomposition); `var` is a second binding form.
**AI-first payoff:** any function is understood from its signature and body alone; any process is tested by feeding messages and checking states; any failure reproduces from seed + log. Nothing ever requires reading code that isn't in front of the agent.
### `var` and `inout`, unpacked (Robert: in)
- `var x` is rebinding that reaches inside a value; identical to `x = x.with(i, v)` observably, in-place on the machine.
- **Rule:** a `var` can never be aliased: no references, cannot be sent to a process, cannot be captured by an escaping closure. Passed to a function it is either copied or declared `inout` (caller's name inaccessible until return; mutation visible in the signature).
- **Unlocks:** loops with accumulators in the form models generate reliably (folds are where off-by-one bugs cluster); in-place algorithms (sort, sieve, DP tables, parser cursors); guaranteed in-place memory rather than hoping Perceus proves uniqueness (Roc's gap); honest mutation via `inout`.
- **Costs:** `let` and `var` are two forms; agents may overuse `var`; `inout` rules must be taught well.
- **Fit:** a `var` lives and dies in one call, never becomes identity. Model unchanged: values immutable and unaliased, processes the only identity.

## Related
- [[d10-immutable-by-default]]
- [[d13-local-var-and-inout]]
- [[d14-processes-are-the-only-identity]]
- [[d12-concurrency-at-the-edges]]
