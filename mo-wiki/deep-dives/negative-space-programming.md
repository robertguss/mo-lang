---
title: "Negative space programming"
created: 2026-09-12
updated: 2026-09-12
type: deep-dive
tags: [negative-space, contracts]
sources: [raw/notion/design-journal-2026-09-12.md]
---

# Negative space programming

Source: [Negative Space Programming](https://double-trouble.dev/post/negativ-space-programming/). Define a program by what it must never do, fail the instant it does. Roots in Power of 10 (two assertions per function) and Tiger Style (Joran Greef: think like a hacker).
**Where negative space lives, weakest to strongest:**
1. Runtime assertions in bodies (what the post describes).
2. Contracts (`requires` / `ensures`) on signatures, visible at spec altitude.
3. Types: make illegal states unrepresentable. Compile-time negative space; best feedback loop for agents.
4. Absent capabilities: no `Network` parameter means no network call. Negative space by construction, free to write.
5. **Explicit `never` clauses** (proposed addition): module/process-level statements of what must never be true. `never ledger.balance < 0`, `never this process sends email`. Runtime-checked, attacked by the simulator, proven when possible; the verification line says which.
**AI-first reframe:** humans are bad at specifying complete behavior and good at saying what must not happen. So the `never` set is the natural human-facing surface. Initial proposal had humans writing it; Robert corrected: humans write nothing. Revised: humans speak it, agents write it, humans read and approve it.
**Design consequences:**
- `never` clauses must render as plain sentences ("a refund never exceeds its charge") since their purpose is to be read by someone not reading code.
- `intent` and `ensures` are agent-authored too, read for context, not judged. The `never` set is the judged part.
- "Think like a hacker" becomes mechanical: deterministic simulator + property-based generation spend a million runs trying to violate every reachable `never`.
- Per the laws, every precondition needs a rejection test, so negative-space testing is required.
**Costs:** `never` clauses can contradict each other or the positive spec (compiler must detect); over-constraining blocks valid solutions (human decision to relax); runtime cost in hot paths (prove-and-remove path earns its keep).

## Related
- [[d19-negative-space-is-the-contract]]
- [[d20-human-pulled-in-when-shape-changes]]
- [[p09-module-header-and-never]]
