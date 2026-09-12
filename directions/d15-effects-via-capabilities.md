---
title: "Direction 15: Effects via capabilities, no effect type system"
created: 2026-09-12
updated: 2026-09-12
type: direction
tags: [effects]
sources: [raw/notion/design-journal-2026-09-12.md]
number: 15
status: liked
origin: "Robert"
---

# Direction 15: Effects via capabilities, no effect type system

A function is pure unless it takes a capability parameter. The signature is the purity proof. (Robert: matches)

## Session 3 note (tension 1: closure capture)

The Koka comparison showed that an anonymous function can capture a capability, so a closure can do I/O its own type does not show. Robert's answer: **in** on Bosque's rule. Anonymous functions are call-arguments only (never bound to a name, stored, or returned) and captures are read-only; named `fn`s capture nothing. So a captured capability cannot outlive the call and the enclosing signature still bounds every effect. Wording of this direction now reads: "the signature is the purity proof, and effects never hide in a value." → [[d31-effects-never-hide-in-a-value|direction 31]].

## Related
- [[effects-and-capabilities]]
- [[d16-direct-style-io]]
- [[p13-capabilities-and-logging]]
