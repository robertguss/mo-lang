# Gaps

One line per gap: file, what was missing, the default used.

- `basics/numbers.mo` — return types of `checked_add` / `saturating_sub` / `wrapping_mul` are not specified; treated `checked_add` as `Option` (`or 0`) and the other two as same-type. Float type name is not in chapter 4; used `Float64`.
- `basics/strings.mo` — whether `bytes` is a field or a method is not specified; used `s.bytes` next to `s.size`.
- `basics/lists.mo` — `reduce` arity is not specified; used `xs.reduce(0, fn(acc, x) acc + x end)`.
- `basics/if.mo` — signed sized ints are not named in chapter 4; used `Int32` so negation is possible.
- `types/generics.mo` — no list head or index in the grammar; `first` is `reduce` plus `or`. How `T` is introduced besides mentioning it is not specified. Trait signatures have no `Self`; used `T`.
- `types/trait.mo` — same `T` in the trait signature; impl uses the concrete type.
- `contracts/flows.mo` — grammar says a `never` body is a comprehension; chapter 4 uses `flows(...)`. Used chapter 4.
- `effects/clock.mo` — chapter 4's `clock.now` has no `within:`; used `clock.now(within: 10.ms)` to satisfy the deadline law. How a test obtains a `Clock` is not specified; used `Clock.fixture` (`fixture` is in chapter 4).
- `effects/pure-vs-effectful.mo` — chapter 4's `events.emit` has no `within:`; passed `within: 50.ms` to satisfy the deadline law.
- `effects/timeout.mo` — nothing says `Clock.now` returns `Timeout`; `tick` always returns `Ok`, and `run` still handles `Error(Timeout)`.
- `effects/narrowing.mo` — no `Fs.read` in chapter 4; passed the narrowed capability through. Used `Fs.fixture`.
- `effects/sim.mo` — how tests obtain a `Clock` under `Mo.Sim` is not specified; used `Clock.fixture`.
- `processes/counter.mo` (and ask, mailbox, invariant, supervisor, pipeline) — `start` / `send` / `ask` / `Handle` are chapter 3 prose, not grammar; treated as ordinary calls. `send` has no `within:` (chapter 3: send never blocks).
- `processes/ask.mo` — how `update` produces the `ask` reply is not specified; the `Get` arm leaves state unchanged.
- `recipes/rate-limiter.mo` — `result.0.tokens(id)` is from chapter 6, not the grammar. Recipe tests cannot call `allow?` (no body); the rejects body constructs `Limiter(capacity: 0)`.
- `rejects/default-parameter.mo` — default parameters are not in the grammar; wrote `name: String = "Mo"` as the illegal form the law forbids.
- `rejects/missing-within.mo` — how a test obtains `Events` is not specified; used `Events.fixture`.
