---
title: "Session 1 — 12 Sep 2026 (night)"
created: 2026-09-12
updated: 2026-09-12
type: session
tags: [meta]
sources: [raw/notion/design-journal-2026-09-12.md]
date: 2026-09-12
session: 1
---

# Session 1 — 12 Sep 2026 (night)

## What happened

- **12 Sep 2026, session 1 (cont).** Negative space programming: Claude laid out five levels and proposed `never` clauses as the human-facing surface. Robert: humans shouldn't write any of it. Revised to speak/write/read split; humans pulled in when the shape changes. Robert: none, the agent takes the crash and fixes it. Type system: Robert chose Rust-plus-refinements from day one. Compilation target: Robert agreed with C-via-Zig then LLVM, and added compile speed as a hard requirement; Claude researched Zig/Roc/Unison and laid out the speed levers. Fast path: interpreter, then C, native backend only if proven necessary. Robert: in. Syntax: Claude proposed Rust/Gleam-shaped and showed an example; Robert rejected it, Ruby is his favorite language and the code must be enjoyable to read. Claude rewrote the example Ruby/Crystal-shaped. Robert: closer, but wants to pick piece by piece. Pieces 14 (modules) and 15 (dot-call sugar, traits, `where` generics) in. Session closed at ~1am Robert's time. [[p13-capabilities-and-logging|Piece 13]] (root-only capabilities, no log statements, typed events) in. Pieces 11 (loops, `fn(x) ... end`) and 12 (in-file tests, `rejects`, `property`) in. Robert intrigued by in-file tests; Claude cited Zig, Pyret, D, Rust, Elixir, Unison. [[p10-process|Piece 10]] (process) confused Robert; clarified with a counter. Robert dropped `.with` for plain `state.count = 0`, then wrote his own version of `apply_refund`: `fn ... end` blocks, no braces, `name: Type`, contracts flowing into the body. That is now the base. Pieces 1-9 originally chosen: braces (not def/end, not indentation), `fn` + Crystal types, bare `=` bindings, `if` rules, `case` with arrows, `try` + predicate `?`, call-style construction + `.with`, contracts above the brace, `module Payments.Refund` dot paths + `never` sentence-and-block.
- **12 Sep 2026, session 1 (cont).** Errors and failure: rain vs broken roof, no try-catch, crash-only bugs with supervisor restart. Robert: definitely in. Robert queued negative space programming for discussion next.
- **12 Sep 2026, session 1 (cont).** Effects and capabilities: Claude laid out effect types vs commands vs capabilities, then the direct-vs-command I/O fork. Conclusion: capabilities as parameters, direct-style I/O with runtime interception, green threads, mandatory deadlines. Robert: matches, capture it.
- **12 Sep 2026, session 1 (cont).** State deep dive: Claude mapped nine state models with pros/cons and proposed a layered synthesis. Robert asked for `var`/`inout` unpacked, then said: in, capture it.
- **12 Sep 2026, session 1 (cont).** Immutability confirmed. Robert: processes at the edges like Go. Robert raised Elm; Claude extracted lessons and proposed the process = Elm-shaped state machine unification. Open: is that too restrictive?
- **12 Sep 2026, session 1 (cont).** Robert switched to exploration mode: no decisions yet. Stated attributes: never OOP, Elixir-style functional, loves the BEAM but wants a single memory-efficient binary. Claude researched Roc, Koka, Hylo, Austral, Pony, Inko and produced the steal list. Open: what "mutable data is great" means.
- **12 Sep 2026, session 1 (cont).** [[q01-comments|Q1]] answered: agents write ~100%, humans read at a high altitude. Claude proposed the two-altitude model. Robert pointed to Tiger Style and NASA's Power of 10 as old ideas to rethink AI-first; Claude mapped them into laws / dead rules / promoted features. Open: laws with no escape hatch?
- **12 Sep 2026, session 1.** Kickoff. Robert: 10+ yrs SWE, first language, motivated by AI. Claude ran a research pass on the 2026 landscape and laid out the three-way fork plus six interview questions. Awaiting answers.

## Interview questions from the kickoff (superseded by the Q pages)

1. ~~Who writes it?~~ **Answered: agents, ~100%.** See Decisions.
1b. ~~Laws with no escape hatch?~~ **Liked, parked.** Revisit once we know the target domain.
1. **First real program?** Web service, CLI, data pipeline, agent harness, game? A language without a target domain dies. *Deferred: Robert wants to explore language attributes first and let the domain fall out.*
2b. ~~Mutability~~ **Answered: immutable data is great** (typo in the original). Immutable by default.
2c. **Processes as Elm-shaped state machines?** Is "a process = state + message type + pure update returning new state and effect commands, and that is the only place state lives" right, or too restrictive? **Liked.** Processes are the only identity. See Directions we like, [[d14-processes-are-the-only-identity|item 14]].
1. **Runtime appetite.** Native via LLVM, WebAssembly, transpile to Rust/Go, or the BEAM (like Gleam)? Transpiling to Rust gets verification tooling and an ecosystem for free.
2. **How radical on syntax?** Familiar Python/TypeScript feel to exploit model priors, or willing to look strange if it buys correctness?
3. **Verification dial.** From "strong types + exhaustive matching" up to "Dafny-style proofs the agent must discharge." Suggested start: runtime-checked contracts with an optional SMT path.
4. **The name.** Is "Mo" decided? What's the story?
5. **Type system spectrum considered:** Go-level (small, boring, repetitive) / Rust-level (traits, generics, enums with data) / refinement types (values in types, SMT-backed) / dependent types (Lean, Idris). **Answered: Rust + refinements.**

## Related
- [[session-02]]
- [[fork-in-the-road]]
- [[idea-backlog]]
- [[q15-the-name]]
