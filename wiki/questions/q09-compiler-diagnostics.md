---
title: "Q9: Compiler diagnostics as the agent's teacher"
created: 2026-09-12
updated: 2026-09-12
type: question
tags: [compiler, agents]
sources: [raw/notion/open-questions-2026-09-12.md]
number: 9
status: answered
answer: in
asked: 2026-09-12
---

# Q9: Compiler diagnostics as the agent's teacher

**Question:** what does an error look like?
**Recommendation:** every diagnostic is a structured record with a fixed shape, rendered two ways: Elm-style prose for humans, JSON for agents. Fields: `code` (stable ID like `MO0412`), `category` (type / contract / capability / flow / law), `location` (semantic ID + line), `what` (one sentence), `why` (the rule and its rationale, one paragraph max), `fix` (zero or more concrete candidate edits, machine-applicable), `confidence`. Errors only; no warnings exist.
**Why:** An agent that receives a candidate fix converges in one loop instead of three. Stable codes mean the fix for `MO0412` is learnable across the whole corpus. The `why` field is how the language teaches its own philosophy to a model that has never seen it, which is the mitigation for zero training data.
✅ **Robert: IN** (session 2). `why` text is written once per code in the compiler's error catalog, which becomes the long-term home of the design philosophy — the catalog is the teaching material. Every `fix` candidate carries a confidence. Warnings rejected as a social mechanism with no one on the other end.

## Related
- [[d29-edit-by-declaration-id]]
- [[q10-semantic-ids-and-editing]]
