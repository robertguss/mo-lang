---
title: "Idea backlog (Claude's early proposals)"
created: 2026-09-12
updated: 2026-09-12
type: deep-dive
tags: [meta]
sources: [raw/notion/design-journal-2026-09-12.md]
---

# Idea backlog (Claude's early proposals)

- **Stable semantic IDs** on every declaration so agents edit by ID instead of fragile text diffs.
- **Intent blocks** that bind a natural-language requirement to a function and its tests, so provenance is part of the source.
- **Capabilities as values with lifetimes.** A function cannot touch the network unless handed the network. Distinguish "what you may do" from "what you actually did."
- **Structured, fix-suggesting compiler errors** so an agent that starts wrong converges in two or three loops. The compiler is the agent's teacher.
- **One canonical formatting**, no options, ever.
- **Tiny grammar**, surface syntax close to something models already know, so knowledge transfers and the zero-training-data problem is softened.
- **Exhaustive result types**, no exceptions from nowhere, no hidden control flow.
- **Effect tracking** so every function declares what it touches (I/O, mutation, DB, network).
- The language's value lives in **what it checks**, not how it looks.

## Related
- [[d29-edit-by-declaration-id]]
- [[q09-compiler-diagnostics]]
