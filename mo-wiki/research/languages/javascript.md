---
title: "JavaScript — Ten Days that Ate the World"
created: 2026-09-13
updated: 2026-09-13
type: research
tags: [history, languages]
sources:
  - "../raw/plang-history-2026-09/deep-dives/10_javascript.md"
---

### Headline

Brendan Eich created JavaScript at Netscape starting April 1995 ([Wikipedia: Brendan Eich](https://en.wikipedia.org/wiki/Brendan_Eich)). He wanted to put Scheme in the browser; his managers wanted Java-like syntax; he combined "much of the functionality of Scheme, the object-orientation of Self, the syntax of Java" and completed the first version in **ten days**. Named Mocha → LiveScript → JavaScript. Shipped in Navigator 2.0 (September 1995). Standardized as ECMAScript 1 (June 1997).

### The three ideas that shaped everything

- **Prototype-based objects (from Self).** No classes required. Objects delegate to other objects.
- **First-class functions with closures (from Scheme).** The one Lisp idea that reached the world at scale.
- **The event loop.** Single-threaded, non-blocking I/O, callback-driven. Later formalized as Promises (ES2015) and `async`/`await` (ES2017).

### What JavaScript got wrong (mostly by accident)

- **Type coercion.** `[] + {}`, `NaN === NaN`, the whole `==` versus `===` saga.
- **`var` scoping.** Function-scoped, hoisted, `undefined`. ES6 `let`/`const` fixed it 20 years later.
- **`this`.** Dynamic binding based on call syntax. Arrow functions fixed it 20 years later.
- **Standardization by feature accretion.** ES4 was killed; ES5 was a compromise; ES6/ES2015 was the reset.

### What JavaScript got right (in retrospect)

- **Ubiquity.** Every browser, every OS, every device. The only language you can rely on being installed everywhere.
- **npm.** The world's largest package registry. Also the world's most-attacked package registry (see [[q17-package-management-and-supply-chain]], [[d30-supply-chain-security]]).
- **The Node.js runtime.** V8 outside the browser gave JavaScript a viable server story.
- **TypeScript.** Microsoft's optional-static-types layer became the way large teams ship JavaScript. Proof that a bolt-on type system can succeed if it stays out of the way.

### What Mo takes

- **Async as language-level.** `async`/`await` was JavaScript's best late addition; structured concurrency ([[d12-concurrency-at-the-edges]]) is Mo's version.
- **TypeScript's lessons.** Gradual typing on top of a dynamic core teaches Mo what static types must do to feel ergonomic to agents.
- **The event-loop model as one option among many.** Mo will not commit to a single concurrency model at the language level; capabilities can select runtimes.

### What Mo refuses

- **Dynamic typing.** For agents, non-negotiable. [[d11-statically-typed]].
- **Type coercion.** No implicit conversions.
- **`null` + `undefined`.** [[q05-option-and-no-nil]].
- **npm-style trust model.** The typosquatting, dependency-confusion, and post-install-script attacks that plague npm are the direct motivation for [[d34-packages-are-recipes]] and [[d30-supply-chain-security]].

### The lasting lesson

JavaScript is the "worse is better" language *par excellence*. Every serious language designer would have made different choices; ubiquity made them irrelevant. But it is also the direct source of the modern supply-chain-attack pattern — package registries as attack surface — that Mo's design treats as an existential threat.

Ten days of language design became 30 years of consequence. Move slowly.

## Related

- [[python]] — the other accidental world-conqueror
- [[go-history]] — a deliberate reaction against JS-scale complexity growth
- [[q17-package-management-and-supply-chain]]
- [[d30-supply-chain-security]]

## Sources

- [Full deep-dive](../raw/plang-history-2026-09/deep-dives/10_javascript.md)
- [Wikipedia: Brendan Eich](https://en.wikipedia.org/wiki/Brendan_Eich)
- [Wikipedia: JavaScript](https://en.wikipedia.org/wiki/JavaScript)
