---
title: "Q10: Semantic IDs and how agents edit Mo"
created: 2026-09-12
updated: 2026-09-17
type: question
tags: [tooling, agents]
sources: [raw/notion/open-questions-2026-09-12.md]
number: 10
status: answered
answer: in
asked: 2026-09-12
---

# Q10: Semantic IDs and how agents edit Mo

**Question:** do agents edit text, or the tree?
**Recommendation:** both, with text as the source of truth. Every declaration gets a stable ID assigned by the toolchain on first appearance and stored in a sidecar the formatter maintains (`.mo.ids`), never in the source. Tools expose `edit(id, new_source)` and `rename(id, name)` so an agent can change a function without a fragile text diff, and the content hash of a declaration (for caching) is separate from its identity (for editing).
**Why:** Text stays the shared language humans and agents read. IDs solve the two agent pain points: edits landing on the wrong line after a concurrent change, and renames breaking references. Keeping IDs out of the source keeps the page clean.
✅ **Robert: IN** (session 2, after a full unpack — see the deep dive "ID-addressed editing"). Settled: the unit of edit is the declaration, which the 70-line rule (Q12) keeps short; a small fixed set of named sub-targets (`.contracts`, `.state`, `.update`) and `insert --after` / `delete`; edits are parsed before applying and rejected whole if broken; optimistic concurrency via `--expect hash:`; `rename` is a semantic operation across files; diagnostics and edits share the ID as join key. Plain-text editing always remains as the never-wrong, more-fragile fallback. (17 Sep 2026: the `.mo.ids` sidecar exists; `edit`, `rename`, `insert`, `delete` are unbuilt and not on the roadmap; agents edit text.)

## Related
- [[id-addressed-editing]]
- [[d29-edit-by-declaration-id]]
