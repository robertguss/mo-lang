---
title: "PL history: lambda calculus through the 1970s"
created: 2026-09-13
updated: 2026-09-13
type: deep-dive
tags: [history, foundations]
sources:
  - "../raw/plang-history-2026-09/history/01_foundations_to_1970s.md"
---

### Headline

Forty years of foundational work that still governs modern language design. The 1930s formal systems (lambda calculus, Turing machines) determined what a language *could* be; the 1950s produced the first high-level languages; the 1960s and 1970s created every paradigm we still argue about.

### Three findings that shape everything

- **Every idea Mo will consider was invented before 1980.** Type inference, garbage collection, first-class functions, algebraic data types, structured concurrency, capability-based security, homoiconicity, ownership — all originated in this window. What has changed is execution: implementation techniques, ecosystem practices, and the compute we can spend on verification.
- **The Curry–Howard correspondence is the deep secret.** Types are propositions, programs are proofs. Every language that takes verification seriously (Lean, Rust with formal semantics, Idris, Dafny, F*) is drawing on this 1930s–60s theoretical stack.
- **Backwards compatibility eats languages.** ALGOL 68 killed ALGOL. PL/I killed IBM's mainframe language story. Wirth kept remaking Pascal → Modula → Oberon rather than accreting features — a discipline Mo should imitate.

### Era 1: Theoretical foundations (1930s–1950s)

- **Lambda calculus** (Church, 1930s) — function abstraction + application + variable substitution. Turing-complete without a machine model. Every functional language descends here ([Wikipedia: Lambda calculus](https://en.wikipedia.org/wiki/Lambda_calculus)).
- **Turing machines** (Turing, 1936) — the machine model. Church–Turing thesis: both formalisms compute the same thing.
- **Curry–Howard correspondence origins** — Curry (1930s) and Howard (1969) formalize the isomorphism between logic and computation.
- **Von Neumann architecture** (1945) — the substrate. Every imperative language is a notation for it.

### Era 2: First high-level languages (1954–1962)

- **FORTRAN** (Backus, 1954–57) — first widely used compiled language. Scientific computing.
- **LISP** (McCarthy, 1958) — symbolic, list-based, homoiconic. See [[lisp]].
- **COBOL** (Hopper et al., 1959) — business computing, English-like syntax, still runs the world's payroll.
- **ALGOL 60** — the reference language of the era. Block structure, recursion, formal syntax (BNF). Never dominant in industry; hugely influential in design.

### Era 3: The 1960s paradigm explosion

- **ALGOL 68** — everything in one language. A cautionary tale in kitchen-sink design.
- **Simula 67** (Dahl & Nygaard) — classes and inheritance. Ancestor of every OO language.
- **BCPL → B → C** — the systems-programming lineage that led to Unix. See [[c]].
- **Pascal** (Wirth, 1970) — teaching language, LL(1) parseable, disciplined.
- **PL/I** (IBM) — attempted to unify FORTRAN + COBOL + ALGOL. Overreached spectacularly.
- **SNOBOL** — string processing; ancestor of regex culture.

### Era 4: The 1970s functional and OO branches

- **Smalltalk** (Kay, Ingalls, Goldberg at PARC, 1972) — objects, messages, live image. See [[smalltalk]].
- **Prolog** (Colmerauer, Kowalski, 1972) — logic programming. Still used in constraint solvers and NLP.
- **Scheme** (Sussman & Steele, 1975) — the minimalist Lisp. First-class continuations, tail calls.
- **ML** (Milner, 1973) — type inference invented here to make LCF theorem-prover tactics safe. See [[ml]].
- **Forth** (Moore, 1970) — stack-based, extensible, still lives in bootloaders and space probes.

### Cross-cutting themes

- **"GOTO Considered Harmful"** (Dijkstra, 1968) — structured programming becomes orthodoxy.
- **The software crisis** (NATO conference, 1968) — the profession admits it does not know how to build large systems.
- **Wirth's Law** — software gets slower faster than hardware gets faster. First articulated here, still true.
- **Compiler technology** — lex/yacc, table-driven parsing, single-pass vs multi-pass debates.
- **Memory management** — Lisp had GC in 1959; C shipped without one in 1972. The split has never healed.

### What Mo takes from this era

- **Static typing with algebraic data types** — the ML lineage, refined ([[d11-statically-typed]], [[d22-rust-plus-refinements-types]]).
- **First-class functions and closures** — from lambda calculus, made practical by Scheme.
- **Structured programming** — no `goto`, block-scoped, disciplined control flow ([[d04-style-rules-become-laws]]).
- **Immutability as default** — the LISP tradition, now widely accepted ([[d10-immutable-by-default]]).
- **Small, teachable core** — the Wirth discipline. Mo aims for a spec small enough to hold in one head (or one agent context).

### What Mo refuses

- **Inheritance-based OO** — Simula's legacy is the wrong abstraction for the AI era ([[d06-never-oop]]).
- **Kitchen-sink design** — no ALGOL 68, no PL/I, no C++ growth curve.
- **Dynamic typing as default** — LISP's flexibility is an agent-hostile substrate.

## Related

- [[plang-history-1980s-to-2000s]]
- [[plang-history-2010-to-2026]]
- [[plang-design-camps]]
- [[c]] · [[lisp]] · [[smalltalk]] · [[ml]]
- [[research-summary-2026-09]]

## Sources

- [Full report](../raw/plang-history-2026-09/history/01_foundations_to_1970s.md)
- [Wikipedia: Lambda calculus](https://en.wikipedia.org/wiki/Lambda_calculus)
- [Ritchie, "The Development of the C Language"](https://www.cs.tufts.edu/~nr/cs257/archive/dennis-ritchie/chist.pdf)
- [Kay, "The Early History of Smalltalk" HOPL II](https://www.cs.tufts.edu/comp/150FP/archive/alan-kay/smalltalk-hopl-ii.pdf)
