---
title: "Lisp — Code Is Data, and Data Is Code"
created: 2026-09-13
updated: 2026-09-17
type: research
tags: [history, languages]
sources:
  - "../../raw/plang-history-2026-09/deep-dives/02_lisp.md"
---
# Lisp — Code Is Data, and Data Is Code


## Headline

John McCarthy started Lisp at MIT in 1958 as an AI language for the IBM 704 ([Wikipedia: Lisp](https://en.wikipedia.org/wiki/Lisp_(programming_language))). The pivotal moment was Steve Russell realizing McCarthy's paper `eval` — intended "for reading rather than computing" — could be compiled to IBM 704 machine code. That accident produced the first interpreter and named the entire tradition.

## The three ideas that shaped everything

- **Homoiconicity.** Programs are lists; lists are data. Macros can generate code using the same functions that manipulate data.
- **Interactive image.** A running Lisp is a mutable environment into which compiled and interpreted definitions are added incrementally — the model every modern REPL descends from.
- **First-class functions.** Directly from Church's lambda calculus; uncommon in mainstream languages until the 2000s (corrected 17 Sep 2026).

## The branches

- **Common Lisp (ANSI 1994).** Kitchen sink. Object system (CLOS), condition system, restarts, powerful macros, over 1,000 pages of spec.
- **Scheme (1975, Sussman & Steele).** Minimalist counter-reformation. ~50-page core, hygienic macros, tail calls, continuations.
- **Clojure (2007, Rich Hickey).** Lisp reborn on the JVM with immutable data structures, software transactional memory, and a values-first philosophy. Hickey's "Simple Made Easy" is required reading.

## What Mo takes

- **S-expressions? No.** Mo has no such commitment — [[grammar|the grammar]] is not stated as LL(1) or LALR(1), and [[q13-implementation-language|Q13]] is about the implementation language, not the grammar class (corrected 17 Sep 2026). But the *idea* of a program as a value your tools can inspect and rewrite carries over into Mo's contract-and-evidence workflow ([[d03-source-carries-its-evidence]]).
- **The image is dead; long live the checkpoint.** Mo does not adopt Common Lisp's persistent-image model, but its interpreter for the edit loop is the same shape: fast round-trip so agents can iterate.
- **Data-oriented values.** Hickey's critique of OO — that classes "complect" state, identity, and behavior — is the direct ancestor of [[d06-never-oop]] and [[d10-immutable-by-default]].

## What Mo refuses

- **Untyped by default.** Lisp's dynamism is agent-hostile — no compile-time contract to verify. Mo picks static types with refinements ([[d22-rust-plus-refinements-types]]).
- **Macros as untyped syntax rewriters.** Mo's metaprogramming, if any, will be typed comptime evaluation à la [[zig]], not text substitution.
- **The reader.** Extensible parsing is antithetical to a stable grammar and stable tooling.

## The lasting lesson

Lisp is the language whose *ideas* other languages steal without adopting the substrate. Garbage collection, first-class functions, dynamic typing, REPLs, higher-order macros, exception systems — all Lisp inheritances. Mo will steal the same ideas the same way: adopt the values-oriented mindset without adopting parentheses or dynamism.

## Sources

- [Full deep-dive](../../raw/plang-history-2026-09/deep-dives/02_lisp.md)
- [Wikipedia: Lisp](https://en.wikipedia.org/wiki/Lisp_(programming_language))
- [The Lambda Papers](https://research.scheme.org/lambda-papers/)

## Related

- [[ml]] — the typed-functional response to Lisp
- [[erlang]] — actor concurrency with immutable data
- [[elixir]] — Ruby ergonomics on top of the same substrate
- [[d06-never-oop]]
- [[d10-immutable-by-default]]
