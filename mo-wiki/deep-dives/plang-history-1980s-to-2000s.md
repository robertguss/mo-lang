---
title: "PL history: 1980s through 2000s"
created: 2026-09-13
updated: 2026-09-13
type: deep-dive
tags: [history, research]
sources:
  - "../raw/plang-history-2026-09/history/02_1980s_to_2000s.md"
---

### Headline

Three decades in which language design became an *industrial* activity, not just an academic one. The 1980s: object orientation goes mainstream (C++, Objective-C, Eiffel) and functional programming standardizes (SML, Haskell, Erlang). The 1990s: the Web and virtual machines (Java, JavaScript) redefine what a language must be. The 2000s: scripting reaches maturity (Ruby, Python) and the JVM/CLR family diversifies (C#, Scala).

### Three findings that shape everything

- **Design by Contract (Meyer, 1985) invented what Mo now calls "spec altitude."** Eiffel put preconditions, postconditions, and invariants *in the language*, not as annotations. Every modern verification tool descends from this. See [[d02-spec-altitude]].
- **The JVM proved managed runtimes were commercially viable.** Java's success — write once, run anywhere; garbage collection at scale; ecosystem gravity — is the template for every runtime after (CLR, V8, BEAM, Erlang HiPE, HotSpot).
- **CPAN invented the ecosystem-as-language.** Perl 5 + CPAN (1995) demonstrated that a language's *package repository* could matter more than its syntax. Every subsequent language (npm, gems, PyPI, crates.io, Hex) has re-litigated this design choice — and inherited CPAN's supply-chain problems ([[d30-supply-chain-security]]).

### The 1980s

**Object orientation goes mainstream.**

- **C++** (Stroustrup, 1979–83) — Simula classes + C efficiency. "Zero-overhead abstraction." See [[cpp]].
- **Objective-C** (Cox, 1984) — Smalltalk messaging over C. Later the substrate for NeXT/macOS/iOS.
- **Eiffel** (Meyer, 1986) — Design by Contract in the language. Preconditions, postconditions, invariants.
- **Ada** (US DoD, 1980–83) — safety-focused; the ancestor of SPARK.

**Functional programming standardizes.**

- **Common Lisp** (Steele et al., ANSI 1994) — multi-paradigm kitchen sink. CLOS, condition system, MOP. See [[lisp]].
- **Scheme R5RS** (1998) — hygienic macros, first-class continuations, minimalist elegance.
- **Standard ML** (Milner, Tofte, Harper; 1990 formal *Definition*) — first mainstream language with full mathematical semantics. See [[ml]].
- **Miranda** (Turner, 1985) — lazy, pure, proprietary. Its closedness spurred the Haskell effort.
- **Haskell 1.0** (April 1990) — the committee's laziness. See [[haskell]].
- **Erlang** (Armstrong, Virding, Williams at Ericsson; 1986) — actors, supervisors, "let it crash." See [[erlang]].

**Scripting and embeddable languages.**

- **Perl** (Wall, 1987) — Unix glue with `$/@/%` sigils. "There's more than one way to do it."
- **Tcl** (Ousterhout, 1988) — embeddable command language. Everything is a string. Ancestor of Lua.
- **PostScript** (Warnock, Geschke; Adobe 1984) — stack-based, Turing-complete page description. Ancestor of PDF.
- **Self** (Ungar, Smith at PARC/Sun; 1986) — prototype-based OO. Invented modern JIT: inline caches, polymorphic inline caches, adaptive recompilation. Direct ancestor of HotSpot and V8.

### The 1990s

**The Web and virtual machines.**

- **Python** (van Rossum, 1989–91) — executable pseudocode. See [[python]].
- **Ruby** (Matsumoto, 1995) — "programmer happiness." Rails (2004) would later be its killer app.
- **Lua** (Ierusalimschy et al., 1993) — small embeddable scripting. Wins in games and embedded systems.
- **PHP** (Lerdorf, 1994) — server-side templates. Powers most of the web by accident.
- **Java** (Gosling, Sun; 1995) — WORA, GC, JVM. See [[java]].
- **JavaScript** (Eich, Netscape; 10 days in May 1995) — the language that ate the world. See [[javascript]].
- **OCaml** (Leroy, INRIA; 1996) — SML lineage with objects, native codegen.

### The 2000s

**The 2000s were consolidation, not revolution.**

- **C#** (Hejlsberg, Microsoft; 2000) — Java-clone that iterated faster than Java. LINQ (2007) brought functional ideas mainstream.
- **Scala** (Odersky, EPFL; 2004) — functional + OO on the JVM. Higher-kinded types, implicits, path-dependent types.
- **F#** (Syme, Microsoft; 2005) — OCaml on .NET.
- **Groovy** (Strachan, 2003) — dynamic JVM language. Grails web framework.
- **Clojure** (Hickey, 2007) — Lisp on the JVM with immutable data structures and STM. "Simple Made Easy" (Hickey, 2011) is required reading for anyone thinking about complexity.
- **Erlang open-sourced** (1998) → **Rails/Django boom** (2004–2008) → **Node.js** (Dahl, 2009) — server-side JS.

### The ecosystem revolution: 1995 → 2010

- **CPAN** (Perl, 1995) — first mass package repository.
- **PyPI** (Python, 2002); **RubyGems** (2003); **npm** (Node, 2010).
- **Maven Central** (Java, 2002) — declarative dependency management for the JVM.
- **Nix** (Dolstra, 2003) — content-addressed derivations. Ahead of its time; ecosystem catches up in the 2020s.

### What Mo takes

- **Design by Contract** — a first-class language feature, not annotations ([[d02-spec-altitude]], [[d03-source-carries-its-evidence]]).
- **Actors + supervisors** — Erlang's crash-and-restart model, minus BEAM ([[d08-beam-qualities-without-the-beam]], [[d12-concurrency-at-the-edges]]).
- **Type classes / traits** — Wadler & Blott's principled polymorphism, now Rust traits.
- **Package manager from day one** — Cargo (2014) will show what this looks like done right; Mo commits to the same discipline ([[d34-packages-are-recipes]]).

### What Mo refuses

- **Class-based OO** — Simula's legacy. [[d06-never-oop]].
- **Laziness by default** — Haskell's genius trap.
- **Late binding as core** — Smalltalk's escape hatch turned into runtime instability.
- **Kitchen-sink standard libraries** — C++, Perl, Common Lisp all suffered.

## Related

- [[plang-history-lambda-to-1970s]]
- [[plang-history-2010-to-2026]]
- [[plang-design-camps]]
- [[cpp]] · [[java]] · [[python]] · [[javascript]] · [[haskell]] · [[erlang]] · [[ml]]

## Sources

- [Full report](../raw/plang-history-2026-09/history/02_1980s_to_2000s.md)
- [Peyton Jones, "A History of Haskell: Being Lazy with Class"](https://simon.peytonjones.org/assets/pdfs/haskell-being-lazy-with-class.pdf)
- [Stroustrup, HOPL-II C++ paper](https://www.stroustrup.com/hopl2.pdf)
- [Eiffel: Design by Contract](https://en.wikipedia.org/wiki/Design_by_contract)
