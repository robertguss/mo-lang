---
title: "Q1: Comments"
created: 2026-09-12
updated: 2026-09-12
type: question
tags: [syntax]
sources: [raw/notion/open-questions-2026-09-12.md]
number: 1
status: answered
answer: in
asked: 2026-09-12
---

# Q1: Comments

**Options:** `#` (Ruby, Python, Elixir) or `//` (Rust, Go, C).
**Recommendation:** `#`.
**Why:** It's the Ruby and Python convention, it's one character, and `//` looks like division to a reader on a phone. Doc comments are just a `#` block directly above a declaration; no separate `##` or `///` form. One comment syntax.
✅ **Robert: IN** (session 2). Single comment form, no block comments, no doc-comment variant. Accepted cost: no commenting-out of regions; agents delete and let history hold it.

## Related
- [[p09-module-header-and-never]]
- [[d27-simple-and-elegant-like-ruby]]
