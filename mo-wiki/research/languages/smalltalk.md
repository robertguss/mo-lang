---
title: "Smalltalk — Objects All the Way Down"
created: 2026-09-13
updated: 2026-09-13
type: research
tags: [history, languages]
sources:
  - "../raw/plang-history-2026-09/deep-dives/03_smalltalk.md"
---

### Headline

Smalltalk was invented at Xerox PARC (1972) by Alan Kay, Dan Ingalls, Adele Goldberg, and colleagues in service of the Dynabook — a "personal, notebook-sized computer" for "children of all ages" ([Kay, HOPL-II Smalltalk paper](https://www.cs.tufts.edu/comp/150FP/archive/alan-kay/smalltalk-hopl-ii.pdf)). Ingalls implemented the first version in about 700 lines of BASIC on a Data General Nova in October 1972.

### The three ideas that shaped everything

- **Everything is an object.** Integers, classes, methods, blocks, stack frames — no primitives, no escapes.
- **Computation is message-passing.** Objects respond to messages; there is no direct field access. Late-binding "of all things" was, for Kay, the *actual* essence of OO — not classes or inheritance.
- **The live image.** A running Smalltalk is a graph of objects you edit in place. Dan Ingalls famously changed bit-style scrolling to smooth scrolling live during Steve Jobs's 1979 PARC visit — "in less than a minute" ([Kay HOPL-II](https://www.cs.tufts.edu/comp/150FP/archive/alan-kay/smalltalk-hopl-ii.pdf)).

### The lineage

- **Smalltalk-72** (BASIC interpreter, Nova; ported to Alto April 1973)
- **Smalltalk-76** (Ingalls et al.; ~50 classes, 180 pages of source, OS + Ethernet + editors + graphics)
- **Smalltalk-80** (first publicly available; metaclasses; the reference)
- **Squeak / Pharo** (open-source descendants, still active)
- **Objective-C** (Cox, 1984 — Smalltalk messaging over C, later powers NeXT/macOS/iOS)

### What Mo takes

- **Nothing directly.** Mo is [[d06-never-oop]] on principle. No classes, no inheritance, no message dispatch as a language primitive.
- **The lesson about tools.** PARC's environment — browsers, inspectors, debuggers, changesets — is the ancestor of every modern IDE. Mo takes the *aspiration* (tooling ships with the language) into [[d02-spec-altitude]] and [[q08-verification-tiers]], not the substrate.

### What Mo refuses

- **Late binding by default.** Agent-written code needs compile-time certainty, not runtime `doesNotUnderstand:` recovery.
- **The image.** A live mutable environment is unshippable and unverifiable; Mo commits to source-first workflows.
- **OO as the organizing principle.** Rich Hickey's critique that classes complect state, identity, and behavior lands squarely; Mo uses functional composition over data ([[d07-elixir-flavored-functional]]).

### The lasting lesson

Smalltalk's cautionary tale for language designers: an unbelievably elegant substrate can lose to less elegant competitors if the deployment model, packaging story, or ABI is wrong. Smalltalk images are hard to diff, hard to version-control, hard to deploy incrementally — problems Mo takes seriously in its [[d34-packages-are-recipes]] model.

## Related

- [[lisp]] — the other "everything is X" language
- [[erlang]] — Joe Armstrong argued Erlang was the *real* OO
- [[d06-never-oop]]
- [[d34-packages-are-recipes]]

## Sources

- [Full deep-dive](../raw/plang-history-2026-09/deep-dives/03_smalltalk.md)
- [Kay, "The Early History of Smalltalk" HOPL II](https://www.cs.tufts.edu/comp/150FP/archive/alan-kay/smalltalk-hopl-ii.pdf)
- [Ingalls, "Design Principles Behind Smalltalk"](https://research.cs.queensu.ca/home/cordy/cisc860/Biblio/drb/DC/ingalls81.pdf)
