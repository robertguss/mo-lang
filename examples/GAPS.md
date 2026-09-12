# Corpus gaps

Each line names a missing or conflicting rule and the default used; these are open decisions, not additions to Mo.

- `basics/numbers.mo`: Numeric method signatures and the float type name are not specified; use the brief's named arithmetic, `Option(UInt32)` for checked addition, and provisional `Float64` at a declared boundary.
- `basics/strings.mo`: The result type of `bytes` is unspecified; use a byte sequence with `.size` rather than invent a byte-count API.
- All `.mo` files: The toolchain currently documents unimplemented stages; examples are source fixtures checked against the draft, not claimed compiled or executed.
- `basics/option.mo`, `basics/result.mo` (and later Option/Result examples): EBNF patterns require named payloads and the prose bans positional construction, but chapter 4 explicitly uses `Some(x)`, `Ok(x)`, and `Error(e)` without defining field names; retain those documented built-in forms only, with named fields for user-defined variants.
- `basics/lists.mo`: List combinator signatures are not declared; use the ordinary seed-first `reduce(seed, fn(total, item) ... end)` call shape and record it as provisional.
- `basics/anonymous-functions.mo` (and later hyphenated paths): Module-to-file mapping does not define hyphenated basenames; use `AnonymousFunctions` for `anonymous-functions.mo`, consistently converting CapCase words to lowercase hyphenated names.
- `basics/anonymous-functions.mo`: EBNF references undefined `params_untyped`; use the chapter 4 `fn(x)` spelling and the grammar's newline block alternative.
- `basics/for.mo`: Range endpoint inclusion is unspecified; break before the endpoint so either interpretation gives the same tested result.
- `types/refinement.mo`: The draft does not settle whether an invalid literal at a refinement boundary is a static error or a runtime rejects case; use the brief's boundary call in `test rejects`, without inventing a constructor.
- `types/generics.mo`: Traits lack a defined name for their implementing type; use the already-documented generic `T` in the trait signature, pending a binding rule, and test the independent unbounded `first` function.
- `contracts/ensures.mo` (and later `assert ... is` examples): EBNF `cmp` incorrectly demands a following range after `is pattern`, and `stmt` omits the separately defined `assert`; use chapter 4's `result is Ok(c) implies ...` and test assertions, including its pattern-binding scope.
- `contracts/ensures.mo`: The grammar specifies `inout` only on parameters and gives no caller marker; pass the local `var` as an ordinary argument.
- `contracts/never.mo`: The lifetime and population of `Type.all` are undefined; retain chapter 4's exact enumeration idiom and test concrete matching values without claiming global-history coverage.
- `contracts/flows.mo`: EBNF allows only a comprehension under `never` and has no capitalized named-argument value; retain chapter 4's explicit `flows(CardNumber, into: Events)` form.
- `contracts/flows.mo`: Alias identity and flow tracking through derived values are undefined; use the grammar's primitive type alias, keep the number inside a struct, and emit no events.
- `effects/clock.mo`, `effects/pure-vs-effectful.mo`: Clock provisioning, its import path, and timeout return type are undefined; use chapter 4's `Clock`/`Time` names and direct `now` value, add the law-required deadline, and test only the budget or pure formatter until a simulator API exists.
- `effects/timeout.mo`: No timeout injection API is defined; directly construct the documented `Error(Timeout)` variant and test the caller's exhaustive handler.
- `effects/narrowing.mo`: Narrowed capability types and permission inspection are unspecified; retain `Fs` at both boundaries, use the documented `scoped(...).read_only`, and test only the scope string. Narrowing is treated as pure permission restriction; the downstream capability-taking call carries `within:`.
- `effects/sim.mo`: No `Mo.Sim` runner, capability fixture, seed, or clock setup API is defined; select it with the documented `use Mo.Sim` and supply a deterministic pure test, leaving actual simulation execution to the future toolchain.
- `processes/counter.mo` (and later process examples): Initial state values and a supervised test harness are undefined; declare state exactly as chapter 4 does, include a supervisor, and test pure update helpers or protocol values without claiming process execution.
- `processes/ask.mo`: `ask` has no declared argument order, error type, or reply operation; use chapter 3's ordinary dot-call shape with the message and deadline, a local Timeout-only error enum, and the read arm's final value as a provisional reply. Test only the reply consumer.
- `processes/mailbox.mo`: No API can pause a consumer or inspect sender crashes; state the sender-crashes rule in intent and test the numeric bound, without pretending to exercise overflow.
- `processes/invariant.mo`: Grammar prose restricts `old` to ensures, while chapter 4 and the brief require `old(state.x)` in invariants; use the documented invariant form and its true-means-violation semantics.
- `processes/supervisor.mo`: Restart-window boundaries and supervision test controls are undefined; use the chapter 4 restart declaration and test the worker's pure reset operation.
- `processes/pipeline.mo`: `send` is named in chapter 3 but has no signature; use an ordinary handle dot call and the law-required `within:`, without `try`, because sends are documented as nonblocking.
- `processes/pipeline.mo`: Supervisor child declarations cannot supply a dependent handle, and startup wiring is unspecified; declare the source's typed handle parameter and both children, leaving harness wiring unresolved rather than inventing startup syntax.
- `tests/property.mo`: The comprehension production permits an expression but chapter 4 uses `assert` in property bodies; follow the documented property example, keeping the generator guard well below overflow.
- `recipes/rate-limiter.mo`: Chapter 6 omits Limiter, ClientId, refill rate, and fixture defaults; use a one-client bucket, a one-minute full-refill test, and the permitted `fixture` spelling with an unspecified baseline Time, all pending recipe-model decisions.
- `recipes/rate-limiter.mo`: Chapter 6 calls an over-capacity burst a rejects test but gives no precondition it could trip; use an ordinary test for a denied Bool result rather than invent a crashing contract.
- `recipes/rate-limiter.mo`, `recipes/pure-recipe.mo`: Recipe signatures have no bodies and materialization/test scoping is unspecified; keep their acceptance tests inside the recipe and a concrete helper test at module bottom.
- `rejects/*.mo`: The brief's negative fixtures necessarily violate their one named law (including forbidden grammar forms); treat the `expect error` target as the sole exception to the positive-file rules.
