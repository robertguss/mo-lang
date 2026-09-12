---
title: "Q11: The platform concept and the standard library"
created: 2026-09-12
updated: 2026-09-12
type: question
tags: [stdlib, runtime, effects]
sources: [raw/notion/open-questions-2026-09-12.md]
number: 11
status: answered
answer: in
asked: 2026-09-12
---

# Q11: The platform concept and the standard library

**Question:** where do I/O primitives live, and how batteries-included is Mo?
**Recommendation:** Roc's split. The **language** has no I/O; it only knows capabilities as types. A **platform** is a package that provides `main`'s `Platform` value and implements the runtime hooks: scheduler, I/O, the simulator. Ship one official platform, `Mo.Server` (files, network, clock, processes, events), and one test platform, `Mo.Sim` (deterministic everything). The **standard library** is Go-sized: collections, strings, JSON, HTTP client and server, time, crypto primitives, and nothing web-framework-shaped. Zero third-party dependencies for the toolchain itself, Tiger Style.
**Why:** Platforms are where the no-escape-hatch law becomes livable: unsafe code exists only in a platform, written and audited once. A batteries-included stdlib is what lets most programs have zero dependencies, which is the single biggest thing Go got right for agents (less choice, less entropy).
**Session 2 additions:** swapping `use Mo.Server.{Platform}` for `use Mo.Sim.{Platform}` in `main` is the whole simulation story, one line. Stdlib list: List, Map, Set, String, Json, Time, Http (client + server), Crypto primitives, Regex. No web framework, ORM, or CLI-args framework. Package ecosystem for domain-shaped things (Postgres, gRPC) is a later question; the stdlib doesn't try to be it.

## Answer

✅ **Robert: IN** (session 2). Reached after an unpack of what a *platform* is: in Ruby `File.read` is built into the language, so any code can touch the OS; in Mo the language cannot touch the OS at all and `main(platform: Platform)` *receives* that ability as a value from the platform package. Stdlib = pure code (`List`, `Json`, `Regex`, HTTP parsing); platform = the only thing that touches the OS.

## Session 3 note

Robert: a database driver (Postgres wire protocol, pooling, TLS) is a **brick**, i.e. stdlib/platform, not a recipe. Rule for the line ([[d34-packages-are-recipes|direction 34]]): if a bug in it is a security or data-loss event, it is first-party code. The stdlib ceiling rises accordingly.

## Related
- [[q16-escape-hatch]]
- [[q17-package-management-and-supply-chain]]
- [[d15-effects-via-capabilities]]
- [[steal-list]]
