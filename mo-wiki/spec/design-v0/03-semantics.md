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
- `Name.start(caps...)` returns a typed `Handle(Name)`. `send` never blocks and has no `try`. `send(message, delay: d)` delivers the message no earlier than `d` after the sending update ends (from `main` or a test, `d` after now): it waits outside the mailbox, so the process's later sends may arrive before it, and it goes in once its time has passed; a crash drops it with the update's other sends, and a target that is down when it is due drops it. A process still never loops or sleeps; the runtime waits. Under `Mo.Sim` simulated time passes to the next delayed send once nothing else is waiting, and the seed orders what is due with the rest (Session 5, step 24). `ask` blocks with a mandatory deadline and returns a `Result`. The deadline travels with the message: inside the arm for a message that carries a reply, `reply_by` is bound to the asker's `Deadline`, a point on the runtime's clock, as `state` is bound; `within: reply_by` waits only what remains and is `Timeout` at once, without making the call, when nothing does; `reply_by.at_most(d)` is the earlier of it and now plus `d`. An arm for a message with no reply has no `reply_by`, and neither do `main` and a test, whose calls take a `Duration`. A message with a reply that arrives by `send` has no asker, so nothing remains of its `reply_by`. Under `Mo.Sim` the clock is the run's own: a fixture call's wait moves it, and `--faults` can take an ask's message only once its deadline has passed (Session 5, step 22). Starting a process is an effect: a function needs a capability parameter to start one (MO0403), and a process may start, and send to, any process its own supervisor names as a `child` without holding a capability, since the supervisor's lines already say the two belong together (Session 5, step 20).
- A message may carry a capability or a handle when its `message` line declares the field, as in `message Accepted(conn: Conn)`: the protocol shows the authority the process receives, and a sender can put in it only what it holds. A handle in a message is copied. A capability in a message moves: once sent it is the receiving process's, and the checker refuses any later use of it in the function that sent it (MO0410); a copy the checker cannot see, such as a start argument sent in one update and used in the next, still reaches the same connection. A struct or an enum field still cannot hold either. A `state` field may hold handles, as `Handle(P)`, `Option(Handle(P))`, `List(Handle(P))`, or `Map(K, Handle(P))`, since a state is owned by exactly one process: a registry keeps a worker per key and routes to it (Session 5, step 24). A state field still cannot hold a capability, a handle inside anything else, or a handle an anonymous function captures, and a function still returns a handle only as it did.
- A process a start call began ends once it has finished: its mailbox is empty, no update of it is running, and no handle to it is held by `main`, by an update in progress, by the start arguments of a process that has not ended, by the state of a process that is up (a crashed process's state holds none once it restarts or stays down), by a send an update holds, or by a reply not yet taken. In a test the surface finds such a process ended when it lists the processes (Session 5, step 24). Its thread and memory are freed, and its id may go to a process started later. A process a supervisor's `child` line starts never ends; it restarts.
- Every mailbox is bounded (`mailbox: N` in the header, default from the laws). A full mailbox crashes the **sender**: overflow means the design lacks flow control, and the fix is `ask` or a larger bound.
- An `invariant "sentence" ... end` block is the condition that holds after every `update`: the process crashes on the message after which it is false. `never` is the negative form.
- `update` is a transaction. On a crash, that message's state writes and buffered outgoing effects are discarded. `clock.now` is frozen per `update`.
- Supervisors are declared, not coded. A supervisor takes the capabilities its children need and hands them down: `child RefundQueue(db, clock, events), restart: :always, max_restarts: 5 per 1.minute`. A process not under a supervisor does not compile. `main` is the root supervisor. No links, monitors, or `receive` in user code.
- Every process is replayable from a snapshot plus its message log. The stdlib is deterministic by law (stable sort, defined map order) so replay is exact.

## Failure

- **Rain** is expected failure: missing file, timeout, bad input. It is an `Error` value in the signature, exhaustive, handled by the caller. Anything from outside the program is rain.
- **A broken roof** is a bug: a `requires`, `ensures`, `invariant`, `never`, overflow, or mailbox overflow tripped. Nobody handles it. The process crashes, the supervisor restarts it from known-good state, and the runtime emits a complete report: seed, message log, state snapshot, the violated clause and its contract chain.
- An agent takes the crash as a task and fixes it. A fix is acceptable only if it passes all tests and contracts and weakens no `never`. If the fix changes the shape, a human is pulled in. That is the only time a human is involved.

## The failure model

What the runtime promises when something breaks, so a program's durability and recovery claims can be read against it. Written after the outside review of 13 Sep 2026 asked for it; every line below is what the toolchain does today, tested by kv and echo, not what it might do.

**What a crash discards.** When `update` crashes, that message's writes to `state` are undone and its buffered sends and emits are dropped. That is the whole transaction. It does not undo an `ask` another process already answered (that process ran its own `update`), a file written through `Fs` (writes fsync before they return, and a write past its deadline is on disk all the same), or bytes already written to a socket. Rollback is local to the crashing process; effects that left it are rain the other side has to handle.

**What timeout means.** The caller stopped waiting. The action may have happened. Each row says what it leaves behind:

| call | after `Timeout` |
|---|---|
| `ask` | the message still arrives; the reply, if any, is dropped |
| `Fs.write`, `append` | on disk, fsynced |
| `Net.write` | the connection is closed, since part of the text may have gone |
| `accept` | the listener keeps listening |
| `read_line` | the partial line is kept for the next read |
| `connect` | nothing |

A `Timeout` on `ask` is therefore not a licence to send again: the first message was delivered exactly once and may have changed the state. A message that may be repeated carries an id the process can recognise, which program 4 tests.

**What restart means.** This is Mo's answer to Armstrong's R6, stable storage: it is a capability's contract, never the supervisor's. A supervisor restarts a crashed process from its initial state with an empty mailbox. The messages waiting for it are lost and their senders are not told; a client waiting in `ask` sees `Timeout`. Restart recovers the service, never the state. A process whose state must outlive a crash writes it through a capability before it replies and replays it when it starts; kv's store, with its append-only log, is the pattern, and a store that does not do this must say `restart: :never` and mean it: the runtime keeps such a process down after its crash, its report says it was not restarted, an `ask` to it is `Down` and a `send` to it is dropped with a `Dropped` event (Session 5, step 29, first tested by `processes/never-restart.mo`).

**When a reply means durable.** Only when the process wrote and fsynced before it replied, as kv's store does under its `never`. The runtime adds nothing here, and the toolchain cannot yet prove the claim independently: kv's `never` checks records the store builds itself, which the review rightly called instrumentation. Mutation tests of the contract machinery are a queued step.

**Poison messages and escalation.** A message that crashes the process on every delivery is dropped with the crash report, since the restart empties the mailbox. A client that keeps sending it burns the supervisor's `max_restarts`; when they are spent the supervisor gives up, `main` crashes, and the program exits 70. The restart budget is the poison bound. Nothing retries on its own.

**Cleanup on crash.** A `Conn` in a crashed process's start arguments closes, restarted or not, so the client sees `Closed`; listeners stay open; other processes keep running; a handle to the crashed process stays valid and reaches the restarted one. Nothing the process promised to send is sent: a worker that tells its listener `Leave` on its happy path tells it nothing on crash, and the listener must not depend on it. A process that must know another has stopped asks it with a deadline.

**Restart with live clients.** A worker per connection crashing loses that connection only. A store restarting loses its queue: every `ask` in flight times out and every client must treat `Timeout` as "unknown, check". Under `--sim` this is injected by the seed, and `mo test --faults P --until F` stops injecting after fraction `F` of the run so a test can assert safety throughout and progress after the faults stop.

**Overload.** A full mailbox crashes the sender, as the laws say, because it means the design has no flow control. The review argues a shared queue wants a result or backpressure instead; Robert's call (13 Sep) is to keep the law and measure it. Program 4 is the measurement.

## The runtime surface

Every running program can be asked what its processes are doing, by an agent debugging it or an operator running it (direction 37). The surface is a capability, `Runtime`, and nothing else: `platform.runtime` is `Some` under `mo run` and `mo test`, so it is on in development, and `None` in a built binary unless the binary was built with the surface in, so a deployed program exposes nothing it did not choose to. `main` passes it down as it passes `Fs`, narrowed by `read_only` for a process that may look but not act. Reading a process's state is the largest authority in the system: a `Runtime` read is a snapshot taken between two updates, never inside one, and it can neither change state nor deliver a message; a `Runtime` that may act can send a process a message it declares and pause or resume it, and every such act is an event. The runtime keeps a bounded ring of structured events (direction 40: an update taken with its duration and the time it waited, a start, an end, a restart, a crash with its report, an overflow, a timeout, a source paused or resumed) that the surface reads, and that the crash report is drawn from; under `Mo.Sim` the ring is what a seed's replay shows. Direction 38's replay from a snapshot is the same ring read backwards and is not in this step.

## Session 5 changes

The rules above already reflect these; this section is the changelog.

Claude (session 5): platform selection moved from a `use Mo.Sim` line to the toolchain (`mo test` is always simulated), because a module that names its platform is a module that can be run against the wrong one. Supervisors take parameters and pass them on `child` lines, because nothing else said where a child's capabilities come from. Both first tested by the interpreter milestone and program 1. The full list of session 5 decisions is at the foot of `grammar.md`.

Session 5, step 24: `send` takes `delay:` (the Processes list), after three programs wanted a timer and program 5's mock slept in an `accept` on a listener nothing connected to; a pending delayed send keeps its target from ending and keeps `main` from finishing, as a message waiting would. Session 5, step 29: unless `main` called `platform.exit`, which ends the program at once and drops every pending delayed send with an event (09, the runtime owns the loop).

Session 5, step 24: a `state` field may hold a handle (the Processes list), after program 5 found that no process could hold a routing table and every request went through one process for the third program running; the runtime counts the handles a state holds as it counts those in start arguments, in both runtimes and under `Mo.Sim`. Structs, enums, and returned values stay as step 18 left them.

Session 5, step 20: a process starts what its own supervisor names as a `child` with no capability, after a probe in step 19 found that since step 18 a process with none could start nothing, so starting a process was an effect no line named; a function still needs a capability to start one.

Session 5, step 20: a message may carry a capability or a handle its `message` line declares, and a capability in a message moves (the Processes list), reversing step 18's refusal for message fields only, so a process can be handed a connection by the runtime or by another process; struct, state, and enum fields stay refused.

Session 5, step 19: a process that has finished ends (the Processes list), after program 4 found that a started process was never freed and a worker per request ran out of memory near 20,000; under `main`, starting processes faster than a statement settles them first hands out the waiting turns, so the finished ones can end.

Session 5, step 18: an `invariant` block holds after every `update` and trips when false, where it was true when broken; `never` keeps the negative form. Fable (step 18, after the outside review): the failure model section, stating what a crash discards, what timeout leaves, what restart loses, when a reply is durable, poison and escalation, cleanup, and overload, all from decisions taken in steps 4, 11, 12, and 15.

Fable (session 5, night, after the research agenda's Armstrong page): "What restart means" now names R6, stable storage, as what it answers; the store recipe is the pattern and program 1 is the test.

Fable (session 5, night, 14 Sep, step 23): the runtime surface section, from Robert's call of 13 Sep night (the surface is a capability, on in development, off in a binary unless held) and the nine questions program 1's worker wanted to ask its service.
