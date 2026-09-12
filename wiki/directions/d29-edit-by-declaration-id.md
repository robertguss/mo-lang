---
title: "Direction 29: Agents edit by declaration ID, not by text position"
created: 2026-09-12
updated: 2026-09-12
type: direction
tags: [tooling, agents]
sources: [raw/notion/design-journal-2026-09-12.md]
number: 29
status: liked
origin: "Robert"
---

# Direction 29: Agents edit by declaration ID, not by text position

(Robert: in, session 2, “fascinating”) Every declaration gets a stable ID in a toolchain-owned `.mo.ids` sidecar; source stays plain text and is the truth. `mo edit <id>`, `mo rename <id>`, `mo insert`, `mo delete`, plus a few named sub-targets. Edits are parsed before applying, carry `--expect hash:` for optimistic concurrency, and share the ID with diagnostics as the join key. Replaces grep-and-replace for essentially all agent edits. See the section below.

## Related
- [[id-addressed-editing]]
- [[q10-semantic-ids-and-editing]]
- [[q09-compiler-diagnostics]]
