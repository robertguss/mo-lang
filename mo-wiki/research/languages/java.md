---
title: "Java — Write Once, Run Anywhere, Forever"
created: 2026-09-13
updated: 2026-09-17
type: research
tags: [history, languages]
sources:
  - "../../raw/plang-history-2026-09/deep-dives/08_java.md"
---
# Java — Write Once, Run Anywhere, Forever


## Headline

James Gosling, Mike Sheridan, and Patrick Naughton started Java at Sun in June 1991 for consumer electronics — set-top boxes and interactive TV ([Wikipedia: Java](https://en.wikipedia.org/wiki/Java_(programming_language))). Renamed from Oak. When the consumer-electronics market did not materialize, Sun pivoted to the emerging Web (1995). "Write Once, Run Anywhere" was the pitch. Java 1.0 shipped in 1996.

## The three ideas that shaped everything

- **JVM as portable target.** A stack-based bytecode + verifier + JIT. The most successful managed runtime ever built; still the reference.
- **Garbage collection as default.** Automatic memory management for a mainstream language, at scale, a decade before Go and Rust re-litigated the question.
- **Safe by construction (of a sort).** No pointer arithmetic, bounds-checked arrays, verified bytecode. Java shipped safety guarantees Windows and Unix programmers had never had.

## What Java got right

- **A stable core language over 30 years.** Backwards compatibility as a religion. Code from 1996 still runs.
- **JIT compilation.** HotSpot's tiered JIT is the reference for adaptive runtime optimization.
- **Ecosystem gravity.** Maven Central, the deepest package ecosystem in mainstream computing. Every JVM language (Scala, Clojure, Kotlin, Groovy) piggybacks.
- **Virtual Threads (JEP 444, Java 21, 2023).** Erlang-style lightweight threads as a runtime feature, retrofitted onto a 27-year-old language. Proof that big changes are possible.

## What Java got wrong (or fixed slowly)

- **Nulls.** `NullPointerException` — Tony Hoare's "billion-dollar mistake" — is baked into the type system.
- **Erased generics.** Backward compatibility forced type erasure; the runtime cannot see generic parameters. See how Kotlin and Scala worked around this.
- **Verbosity.** `AbstractSingletonProxyFactoryBean` is a real class. Getter/setter culture.
- **Checked exceptions.** A great idea in theory that ossified into swallowed `catch` blocks in practice.

## What Mo takes

- **Bytecode-first is optional but tempting.** Mo's compilation strategy is interpreter → C via Zig ([[d24-compile-to-c-via-zig]]), but the JVM's success shows a verified-bytecode target is a real option for pluggable deployment.

  17 Sep 2026: settled the other way — the bytecode VM is Mo's reference runtime and the C backend is checked against it ([[d36-vm-first-runtime|d36]]).
- **JIT lessons.** HotSpot's tiered compilation and profile-guided optimization inform any adaptive-runtime decisions.
- **Stability as a feature.** The Java compatibility contract is aspirational for Mo.

## What Mo refuses

- **Nulls.** [[q05-option-and-no-nil]] — `Option[T]` is not optional.
- **Class-based OO.** [[d06-never-oop]] — the whole enterprise object hierarchy is what Mo is *against*.
- **Runtime reflection as core.** Metaprogramming happens at comptime, not by reading class metadata at runtime.
- **Checked exceptions.** Errors as values, à la Rust `Result` ([[rust]]).

## The lasting lesson

Java is proof that **runtime + ecosystem + backward compatibility** can carry a mediocre language for 30+ years. The JVM is the greatest engineering achievement of the family. Mo's ambition is smaller: not to own an entire ecosystem, but to interoperate with existing ones (C via [[d24-compile-to-c-via-zig]]) without inheriting the JVM's operational weight.

## Sources

- [Full deep-dive](../../raw/plang-history-2026-09/deep-dives/08_java.md)
- [Wikipedia: Java](https://en.wikipedia.org/wiki/Java_(programming_language))
- [Wikipedia: James Gosling](https://en.wikipedia.org/wiki/James_Gosling)

## Related

- [[cpp]] — the OO ancestor Java tried to fix
- [[go-history]] — Google's post-C++ answer, which also drew Java's server users (corrected 17 Sep 2026)
- [[rust]] — memory safety without a GC
- [[d06-never-oop]]
- [[d36-vm-first-runtime]]
