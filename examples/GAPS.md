# Corpus gaps

Places where a program needed something `spec/grammar.md` and `spec/design-v0/04-syntax.md` do not define. One line per gap: the first file that needed it, what was missing, the default the corpus uses. Robert decides; the corpus only records.

- `basics/bindings.mo`: bindings carry no type and nothing gives an unsuffixed literal (`1`, `1_000`) its type. Default: the literal takes its type from its use (a parameter, the return type, the other operand).
- `basics/numbers.mo`: no names are given for sized integer or float types. Default: `UInt16`, `UInt32`, `UInt64`, `Int32`, `Float64`, extending chapter 4's `UInt32` and `UInt64`.
- `basics/strings.mo`: "`bytes` is bytes" does not say whether `bytes` is a count or a sequence. Default: `word.bytes.size`, so `bytes` is the byte sequence and `size` counts it.
- `basics/tuples.mo`: `if ... else ... end` as the last line of a body can parse as `if_stmt` or as the `if` expression. Default: it is the expression and gives the body its value (the rule the grammar already relies on for `Ok(updated)`).
- `basics/lists.mo`: `params_untyped` (anonymous function parameters) is used but never defined. Default: comma-separated plain names, `fn(total, x) ... end`.
- `basics/lists.mo`: the argument order of `reduce` is not given. Default: `xs.reduce(start, fn(acc, x) ... end)`.
- `basics/option.mo`: the pattern production requires `field: pattern` inside a variant, but chapter 4 writes `Ok(c)` and the grammar's own comment says `Ok(c)`. Default: `Ok`, `Error`, and `Some` take one positional pattern; every user-declared variant uses `field: pattern` (no field-name punning, so chapter 4's `Enqueue(request)` form is avoided).
- `basics/result.mo`: the grammar's `add` production is right-recursive, so `a - b - c` would group as `a - (b - c)`. Default: no file chains `-`; each subtraction has one operator.
- `basics/for.mo`: nothing says whether the range `1..100` includes `100`. Default: undecided; the file's result does not depend on it.
- `basics/anonymous-functions.mo`: module segments are CapCase but the brief's file names are hyphenated, and "file path equals module path" gives no case mapping. Default: `Basics.AnonymousFunctions` lives at `basics/anonymous-functions.mo` (lowercase, a hyphen between words).
- `types/refinement.mo`: no way to construct a refined value. Default: a value of the base type (here a literal) is checked when it crosses a boundary into a `Percent` parameter, and a `Percent` does arithmetic with plain `UInt32`.
- `types/refinement.mo`: `test rejects` is defined as tripping a `requires`, but the brief wants one at a refinement boundary. Default: a failed refinement check counts as a tripped contract for `test rejects`.
- `types/generics.mo`: a trait signature has no name for the implementing type (pick 15: no `self`). Default: `Self`, which parses as a TypeName; each `impl` writes the concrete type.
- `types/generics.mo`: no stdlib trait names exist (pick 15's `Comparable` is only an example). Default: the bound names a trait declared in the same file.
- `contracts/ensures.mo`: no call-site marker for an `inout` argument. Default: a plain `add(cart, 500)` on a `var`; chapter 3 makes the caller's name unusable until return.
- `contracts/never.mo`: `Type.all` (chapter 4's `Refund.all`) is never defined. Default: used as chapter 4 uses it, meaning every value of that type the program holds.
- `contracts/flows.mo`: the `never` production requires a `for` comprehension, but chapter 4's `flows(CardNumber, into: Events)` has none. Default: chapter 4's form, a `never` whose block is the single `flows(...)` call.
- `effects/clock.mo`: chapter 4 calls `clock.now` and `events.emit` without `within:`, but chapter 2 says every effectful call carries a deadline. Default: the law wins; every capability call passes `within:` and returns a `Result`, including `clock.now(within: 10.ms)`.
- `effects/clock.mo`: nothing says what error type a capability call returns, or how `try` turns its failure into the caller's enum. Default: as chapter 4's refund does, the caller's enum has the matching variant (`Timeout`, `Missing(path:)`) and `try` delivers the failure there.
- `effects/clock.mo`: tests cannot obtain a capability, because only `main` gets a `Platform` and `main` is outside the corpus. Default: `Clock.fixture()` and `Fs.fixture()`, by analogy with chapter 4's `Charge.fixture`. A fixture clock is frozen, as `clock.now` is inside `update`.
- `effects/clock.mo`: no type name for `10.ms` or `1.minute`. Default: `Duration`; `Time - Time` gives a `Duration`, and `Time + Duration` gives a `Time`.
- `effects/pure-vs-effectful.mo`: no way to make a `Time` value without a clock (chapter 4's `t0` is undefined). Default: `Time.fixture()`.
- `effects/timeout.mo`: `Fs` has no operations named beyond `scoped` and `read_only`. Default: `fs.read(path, within: d)`, giving the file's text as a `String`.
- `effects/timeout.mo`: no way to make a fixture capability slow. Default: `Fs.fixture(delay: 1.minute)` times out every call, and a plain `Fs.fixture()` is an empty file system where every read is `Missing(path:)`.
- `effects/narrowing.mo`: no type is given for a narrowed capability, and nothing says whether narrowing needs `within:`. Default: `fs.scoped(...).read_only` is still an `Fs`, and narrowing performs no effect, so it takes no `within:`.
- `effects/sim.mo`: the surface of `Mo.Sim` is undefined, and so is what a bare `use Mo.Sim` brings in. Default: the `use` line swaps in the simulated platform for this module's tests, and the test uses the same `Clock.fixture()` as the other files.
- `processes/counter.mo`: `state` fields have no initial values. Default: each field starts at its type's zero (`0`, `""`, `[]`).
- `processes/counter.mo`: nothing shows how a test starts a process or sends to one (`main` is outside the corpus). Default: `Counter.start()` (chapter 3's `Name.start(caps...)`) and `handle.send(Message)`.
- `processes/counter.mo`: `send` has no stated result, and a process's state cannot be read without `ask`. Default: `send` is a statement with no value, and this file's test has no `assert`.
- `processes/ask.mo`: nothing says how `update` replies to an `ask`. Default: the arm for a message with a reply type ends in the reply value (`Total: state.votes`).
- `processes/ask.mo`: the error type of `ask` and the order of messages are not given. Default: `handle.ask(Message, within: d)` returns a `Result` checked with `is Ok(...)`, and messages from one sender arrive in the order sent.
- `processes/mailbox.mo`: no integer type is given for `size`. Default: `UInt32`.
