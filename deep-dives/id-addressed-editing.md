---
title: "ID-addressed editing"
created: 2026-09-12
updated: 2026-09-12
type: deep-dive
tags: [tooling, agents]
sources: [raw/notion/design-journal-2026-09-12.md]
---

# ID-addressed editing

**The problem:** agent editing tools today use `str_replace` (fails on non-unique or already-changed text), line ranges (wrong the moment anything above moves), or whole-file regeneration (burns context, hides the real diff). Root cause: the edit is addressed by text position, but the agent thinks in declarations.
**The move:** the unit of edit is the unit of meaning. `mo edit m7q2k --with refund.new.mo` replaces one declaration. Sounds coarse, but the 40-line function law makes a declaration always fit one edit and one screen; the laws and the editing model reinforce each other.
**What string editing cannot give:**
- **Atomic and parsed.** The new declaration is parsed before the file is touched; a broken edit is rejected whole. A file is never left half-broken.
- **Optimistic concurrency.** `--expect hash:9f31…` → rejected if another agent changed it since. Parallel agents on one module without locks.
- **Semantic rename.** Definition, every call site, `use` lines, and test references across files in one step. No grep false positives.
- **Same address as diagnostics.** A [[q09-compiler-diagnostics|Q9]] `fix` names `id + line`; it lands on the right declaration even after other edits.
**Granularity:** the whole declaration, plus a small fixed set of named sub-targets matching the spec-altitude blocks: `<id>.contracts`, `<id>.state`, `<id>.update`; `insert --after <id>`; `delete <id>` (fails if referenced). Nothing finer — needing a one-line edit means the function is too big.
**What stays text:** the `.mo` file. Humans read text on phones (Unison's store is where people bounce off); git/diff/grep/editors work for free; text editing remains as a never-wrong fallback.
**Costs:** `.mo.ids` is committed and can conflict only when two agents *add* declarations at once (`mo ids rebuild` resolves; existing IDs never move); agents must learn the tool exists (they learn it from diagnostics, since every fix names an ID); whole-declaration edits cost more tokens than a one-line replace, bounded by the 40-line cap.

## Related
- [[d29-edit-by-declaration-id]]
- [[q10-semantic-ids-and-editing]]
