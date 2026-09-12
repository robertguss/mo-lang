# 1. Premise

## The world Mo is for

- Agents write nearly 100% of the code. Humans no longer write or closely review bodies.
- Humans still read. They read intent, contracts, effects, and what the toolchain has verified. That layer is the **spec altitude**. Bodies are the **implementation altitude**, collapsed by default.
- Since review is gone, trust comes from what the compiler can check, not from what a person promised. The source carries its own evidence.
- Style rules that were enforced socially (Tiger Style, Power of Ten) become laws enforced by the compiler.

## What Mo is

- Functional and procedural. No classes, no inheritance, no objects.
- Immutable values by default, with mutable value semantics inside a function (`var`) and `inout` parameters. No aliasing, ever.
- Statically typed, inferred inside bodies, declared at every function boundary. Enums with data, small traits, generics with bounds, refinement types on primitives.
- Effects via capabilities, no effect type system. A function is pure unless it takes a capability parameter.
- Concurrency at the edges: isolated processes, each an Elm-shaped state machine, supervised. Processes are the only identity in the language.
- Two kinds of failure that never cross: expected failure is a value, a bug crashes the process.
- One static binary. Compile speed is a first-class requirement, because compile time is the latency of the agent loop.
- As simple and elegant as Ruby and Python. Ruby's look with Go's discipline. Zero corpus, so bodies borrow shapes models already know; novelty is spent only where semantics need it.

## The null hypothesis

Agents might do as well or better in an existing language with Mo's checks bolted on. The evidence for that case is real: zero-shot code in a no-corpus language scores near 0% on hard tasks, Python is still the best action language for agents, and Quasar gets most of its gains from a Python subset with guarantees underneath. Of 49 agent-first languages catalogued, four publish head-to-head numbers, and none by a third party.

Mo's answer has to be measured, not argued. Three things an existing language cannot be retrofitted with, and which the program menu must show paying off:

1. **Capabilities as permissions**, down to the function parameter, so a package's authority is visible at install and provable at compile time.
2. **No try-catch, no unwrap, no escape hatch in application code**, so a bug can never be turned into a handled outcome.
3. **Bounded everything**: loops, waits, mailboxes, function size, with a supervisor and a replay log as the only recovery story.

If a Quasar-style subset of Go or Python gets most of the same benefit on the same tasks, that result changes the project. The control run is on the milestone list.
