---
title: "Steal list: what to take from other languages"
created: 2026-09-12
updated: 2026-09-17
type: deep-dive
tags: [research, philosophy]
sources: [raw/notion/design-journal-2026-09-12.md]
---

# Steal list: what to take from other languages

**Framing:** Go ships a scheduler and GC inside every binary and nobody calls it a VM. Inko and Pony prove Erlang-style isolated processes and message passing work natively in one binary. Mo can have a small linked-in runtime and still meet the single-binary bar. What we lose without the BEAM: hot code loading and the mature distribution layer. Probably fine.
### From Ruby (and Crystal)
- **Steal:** the reading experience. `def`/`end`, `case`/`when`, blocks with `do |x|`, `unless`, trailing conditionals, predicate methods ending in `?`, keyword arguments, everything is an expression.
- **Steal from Crystal:** proof that Ruby's syntax survives static types and native single binaries. `name : Type` annotations.
- **Leave:** five ways to write everything, optional parens as a choice, monkey patching, metaprogramming, dynamic typing, exceptions.
### From Elixir / BEAM
- **Steal:** processes as the unit of isolation, message passing as the only sharing, supervision trees, let-it-crash. AI-first twist: a crashed process + seed + message log is a contained, reproducible task for an agent. Failure becomes a unit of work.
- **Steal:** pattern matching everywhere, tagged results (`ok` / `error`), the pipe operator.
- **Adapt:** immutable data with structural sharing, implemented via Perceus-style reference counting with in-place reuse rather than per-process GC.
- **Leave:** dynamic typing, hot reload, Erlang term format, the VM.

  17 Sep 2026: two of these were taken after all — the bytecode VM is Mo's reference runtime ([[d36-vm-first-runtime|d36]]) and hot reload is [[d39-hot-code-reload|d39]].
### From Rust
- **Steal:** enums with data, exhaustive matching, Result/Option, no null, no exceptions, traits not classes, "if it compiles it works."
- **Steal:** compiler-as-teacher diagnostics, then go further: structured, machine-consumable errors with suggested fixes.
- **Adapt:** ownership guarantees (no aliasing+mutation, no data races) without the full borrow checker. Lifetimes are the biggest failure source for humans and agents alike; Hylo/Inko get the safety via value semantics and single ownership.
- **Leave:** lifetimes, macros, async coloring, trait-solver complexity, unsafe.
### From Go
- **Steal:** single static binary, one-flag cross-compilation, fast builds, one formatter with zero options, one build tool, batteries-included stdlib so most programs need no deps.
- **Steal:** small language (~25 keywords). Simplicity is the AI-first feature.
- **Adapt:** ceiling on abstraction. Go says no by omission; Mo says no by law.
- **Leave:** nil, GC, `if err != nil`, implicit interfaces.
### From Elm
- **Steal:** zero runtime exceptions as a guarantee, not a goal. Proof that no-escape-hatch is achievable in a real language.
- **Steal:** effects as data. Pure functions return effect descriptions (`Cmd`); the runtime performs them. Inspectable, testable without mocks, and the natural hook for capabilities: the runtime refuses commands the process was not granted.
- **Steal:** compiler-as-patient-friend error messages (the origin of Rust's). AI-first version adds a structured form: category, location, likely cause, candidate fix.
- **Steal:** enforced semantic versioning by API diff. Mo can go further: a changed contract forces a version bump, not just a changed signature.
- **Steal:** the discipline of no. No custom operators, no user-level FFI (ports only), unchanged since 2019. A stable target is a feature for a language models must learn.
- **Steal:** replay/time-travel falls out of state + message log. Same destination as deterministic simulation.
- **Leave:** web-only, slow BDFL cadence, no abstraction over types (real boilerplate; Mo needs traits or similar).
**Unification spotted:** The Elm Architecture, an OTP GenServer, and a Redux reducer are the same shape: state + message + pure `update` returning new state and effects. Proposal: Mo has exactly one stateful construct, the process, and it is Elm-shaped. Everything inside is pure. Let-it-crash, replay, and agent testing (feed messages, check states) all fall out.
### From languages nobody is looking at
- **Austral:** capabilities as linear values. No filesystem access without an unforgeable, consumable token. Cleanest foundation for agent permissions. Shares our anti-magic, small-enough-for-one-head philosophy. [austral-lang.org](https://austral-lang.org/)
- **Koka:** effect types with handlers; Perceus compiles to plain C with no GC. Effects in the signature = how the spec altitude declares what a function touches. Possibly the single most AI-first feature. [koka-lang](https://github.com/koka-lang/koka)
- **Pony:** reference capabilities: the type says who may read and who may write, so mutable data moves between actors with no copies and no locks. Six caps is too many; the core idea is gold. [Pony reference capabilities](https://tutorial.ponylang.io/reference-capabilities/reference-capabilities.html)
- **Hylo:** mutable value semantics. Mutate locals in place, but no two names ever alias the same memory. Feels functional, runs like C. Possible resolution of functional-vs-mutable. [hylo-lang.org](https://hylo-lang.org/)
- **Roc:** the platform concept. The language has no I/O; a platform provides it. Same language for embedded, server, or agent sandbox. Unsafe parts live in the platform, not the language, which supports no-escape-hatch laws. [roc-lang.org](https://www.roc-lang.org/)
- **Inko:** existence proof of Erlang-style processes + deterministic memory + single ownership, natively, one binary. [inko-lang.org](https://inko-lang.org/)

## Related
- [[d09-primary-inspirations]]
- [[research-summary-2026-09]]
- [[d08-beam-qualities-without-the-beam]]
- [[d12-concurrency-at-the-edges]]
- [[language-landscape]]
