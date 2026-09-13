---
title: "Erlang / BEAM — Let It Crash, Then Restart"
created: 2026-09-13
updated: 2026-09-13
type: research
tags: [history, languages]
sources:
  - "../raw/plang-history-2026-09/deep-dives/06_erlang.md"
---

### Headline

Joe Armstrong, Robert Virding, and Mike Williams built Erlang at Ericsson (1986) for telephone switches with a brutal spec: distribution, fault tolerance, soft real-time, hot swapping, non-stop availability ([Wikipedia: Erlang](https://en.wikipedia.org/wiki/Erlang_(programming_language))). The AXD301 switch shipped in 1998 with over one million lines of Erlang and reported nine nines of availability.

### The three ideas that shaped everything

- **Isolated processes, share nothing, message-pass.** Lightweight processes with independent heaps; failure of one cannot corrupt another. Kay-style OO, done for real.
- **"Let it crash."** Defensive programming does not scale. Design supervisor trees that restart failed children into a known-good state.
- **Hot code swap.** Two versions of a module coexist; running processes migrate at call boundaries. Zero-downtime deploys as a language feature.

### Why it matters more than its adoption

Erlang is a small language commercially, but its runtime is the reference implementation of resilient concurrent computing. WhatsApp scaled to a billion users on a handful of BEAM machines. RabbitMQ, CouchDB, and Ejabberd all live on BEAM.

### The lineage

- Prolog prototype (1986) → BEAM VM work (1992) → open source (1998).
- Elixir (Valim, 2011) reused the BEAM but gave it Ruby-family syntax and macros — the more approachable descendant.
- Gleam (Louis Pilfold, 2019+) added static types on top of the BEAM.

### What Mo takes

- **The failure model.** Process isolation + supervision is [[d08-beam-qualities-without-the-beam]] — the *pattern* without the runtime. Structured concurrency at the edges ([[d12-concurrency-at-the-edges]]).
- **Message-passing over shared memory.** Concurrency stories built on shared mutable state have failed everywhere; Mo commits to isolated units communicating explicitly.
- **Small language, big library.** BEAM/OTP is proof that a tiny core plus a rich supervised-process library beats a giant kitchen-sink language.

### What Mo refuses

- **The BEAM as substrate.** Interpreted bytecode with per-process heaps has a performance floor that a compiled Mo can beat by orders of magnitude for CPU-bound work.
- **Dynamic typing.** Erlang was untyped until Dialyzer bolted a success-type analysis on later. Mo is statically typed from day one ([[d11-statically-typed]]).
- **Prolog-derived syntax.** Agents parse LR grammars more reliably.

### The lasting lesson

Erlang proved that **isolation + explicit failure + supervision** produces systems more reliable than any static analysis in the world. Mo inherits the *architecture* — actors, mailboxes, supervisors, structured concurrency — while shifting the implementation to a compiled, statically typed substrate.

Joe Armstrong's rule: "The world is concurrent; make your language concurrent too."

## Related

- [[elixir]] — Ruby-flavored Erlang
- [[d07-elixir-flavored-functional]]
- [[d08-beam-qualities-without-the-beam]]
- [[d12-concurrency-at-the-edges]]
- [[lisp]] — the other language with pattern matching in its DNA

## Sources

- [Full deep-dive](../raw/plang-history-2026-09/deep-dives/06_erlang.md)
- [Wikipedia: Erlang](https://en.wikipedia.org/wiki/Erlang_(programming_language))
- [Brown, "Erlang design history"](http://www.macs.hw.ac.uk/splv/wp-content/uploads/2019/08/brown2019_erlang.pdf)
