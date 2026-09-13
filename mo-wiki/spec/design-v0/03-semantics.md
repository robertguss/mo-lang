# 3. Semantics

Five ideas, one per layer. Each is chosen so that a function can be understood from its own signature and body, and a process from its messages and state. Nothing requires reading code that isn't in front of the agent.

## Values

- All data is an immutable value with value semantics. Structs, enums with data, lists, maps, sets, strings (UTF-8; length is graphemes, `bytes` is bytes).
- `x = expr` binds once per scope. `var x = expr` allows in-place change, and the compiler guarantees a `var` is never aliased: it cannot be referenced, sent to a process, or captured by an anonymous function. Passed to a function it is copied unless the parameter is `inout`, in which case the caller's name is inaccessible until return.
- Refinement types constrain primitives: `type Money = UInt64 where value <= 1_000_000_00`. The check runs at every boundary.
- `Option(T)` with `Some`/`None`, and `value or default` as the only shorthand. `Result(T, E)` with `Ok`/`Error`.
- Equality is structural. There is no identity for values.

## Functions

- Pure by default. Dot calls are sugar for first-argument functions: `charge.refunded?` is `refunded?(charge)`.
- Contracts (`requires`, `ensures`) sit between the signature and the body and are part of the spec altitude. They run in every build. Contract expressions are evaluated in unbounded mathematical integers so the spec itself cannot overflow.
- Traits list functions a type promises; `impl` provides them. One `impl` per type and trait pair, and an exposed impl lives only in the type's or the trait's module. No inheritance, no trait objects in v0.
- Anonymous functions exist only as call arguments (`xs.filter(fn(x) x > 0 end)`). Named functions are first-class values and carry their capabilities in their own signatures.

## Effects

- A **capability** is an unforgeable value (`Ledger`, `Clock`, `Fs`, `Network`, `Events`) that must be held to perform an effect. Capabilities are obtained only at the program root, `fn main(platform: Platform)`, passed down explicitly, and narrowed on the way (`fs.scoped("/var/app").read_only`).
- A function with no capability parameter is provably pure. The signature is the proof, and chapter 2's closure law keeps it honest.
- Effectful calls are direct style: `db.find_charge(id, within: 200.ms)` reads like Go and blocks like Erlang. Under the hood it suspends, hands a command to the runtime, and resumes. The runtime is the single interception point for capability checks, replay logging, deadlines, and fault injection. Green threads; no `async`, no function coloring.
- The language has no I/O. A **platform** package provides `Platform` and implements the runtime hooks. `Mo.Server` is the real one; `Mo.Sim` is deterministic everything. A module never names its platform: `mo test` runs on `Mo.Sim`, `mo run` on the real one.

## Processes

- A process is the only thing with identity and the only thing that changes over time. Its capabilities are its parameters, its `state` block is the box, its `message` lines are its protocol, and `update(state, message)` is the one function that changes the box. `state` is implicitly mutable inside `update`.
- `Name.start(caps...)` returns a typed `Handle(Name)`. `send` never blocks and has no `try`. `ask` blocks with a mandatory deadline and returns a `Result`.
- Every mailbox is bounded (`mailbox: N` in the header, default from the laws). A full mailbox crashes the **sender**: overflow means the design lacks flow control, and the fix is `ask` or a larger bound.
- An `invariant "sentence" ... end` block is the condition that holds after every `update`: the process crashes on the message after which it is false. `never` is the negative form.
- `update` is a transaction. On a crash, that message's state writes and buffered outgoing effects are discarded. `clock.now` is frozen per `update`.
- Supervisors are declared, not coded. A supervisor takes the capabilities its children need and hands them down: `child RefundQueue(db, clock, events), restart: :always, max_restarts: 5 per 1.minute`. A process not under a supervisor does not compile. `main` is the root supervisor. No links, monitors, or `receive` in user code.
- Every process is replayable from a snapshot plus its message log. The stdlib is deterministic by law (stable sort, defined map order) so replay is exact.

## Failure

- **Rain** is expected failure: missing file, timeout, bad input. It is an `Error` value in the signature, exhaustive, handled by the caller. Anything from outside the program is rain.
- **A broken roof** is a bug: a `requires`, `ensures`, `invariant`, `never`, overflow, or mailbox overflow tripped. Nobody handles it. The process crashes, the supervisor restarts it from known-good state, and the runtime emits a complete report: seed, message log, state snapshot, the violated clause and its contract chain.
- An agent takes the crash as a task and fixes it. A fix is acceptable only if it passes all tests and contracts and weakens no `never`. If the fix changes the shape, a human is pulled in. That is the only time a human is involved.

## Session 5 changes

The rules above already reflect these; this section is the changelog.

Claude (session 5): platform selection moved from a `use Mo.Sim` line to the toolchain (`mo test` is always simulated), because a module that names its platform is a module that can be run against the wrong one. Supervisors take parameters and pass them on `child` lines, because nothing else said where a child's capabilities come from. Both first tested by the interpreter milestone and program 1. The full list of session 5 decisions is at the foot of `grammar.md`.

Session 5, step 18: an `invariant` block holds after every `update` and trips when false, where it was true when broken; `never` keeps the negative form.
