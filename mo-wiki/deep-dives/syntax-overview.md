---
title: "Syntax: how we got to Ruby's look with Go's discipline"
created: 2026-09-12
updated: 2026-09-12
type: deep-dive
tags: [syntax, philosophy]
sources: [raw/notion/design-journal-2026-09-12.md]
---

# Syntax: how we got to Ruby's look with Go's discipline

**AI-first constraint:** Mo has zero corpus, so bodies borrow shapes models know cold; novelty is spent only where semantics need it (`intent`, `never`, `requires`, `ensures`, `process`, `within:`, `verified by`).
**Families considered:** Rust-shaped (Gleam), Python-shaped, Elixir-shaped, Go-shaped. Claude first recommended Rust/Gleam-shaped braces and showed a full example. **Robert rejected it:** Ruby is his favorite language to read and write; the code must be enjoyable. Rewritten Ruby/Crystal/Elixir-shaped.
**Syntax choices in the Ruby-shaped draft:**
- `def`/`end`, `case`/`when`, `do |x|` blocks, `unless`, trailing `if`. Keywords, not braces.
- Contracts (`requires`/`ensures`) are the first lines of a method, like Rails validations at the top of a model. Above the body, collapsible.
- Predicate methods end in `?` (Ruby), so Rust's `?` propagation is replaced by Zig's `try` prefix: `charge = try db.find_charge(id, within: 200.ms)`.
- `ok` / `error` are lowercase constructors: `return error AlreadyRefunded(id) if ...`.
- Immutable update via `.with(field: value)`.
- Crystal-style `name : Type`; generics with parens `Result(Charge, RefundError)`.
- `struct` / `enum` / `type X = ... where ...` for refinements.
- `process` block with `state ... end`, `invariant`, `message` declarations, one `def update`.
- `test "..."` and `test rejects "..."` blocks; `verified by ...` line at module end.
**Discipline:** Ruby offers five ways to write everything; Mo offers one. Optional parens, `do`/`end` vs braces, `unless` vs `if !`: all resolved by the formatter so agents never choose.
**Open tension noted:** `log.warn(e)` inside a process should require a `Log` capability. Logging is the effect everyone wants everywhere.

## Related
- [[d26-developer-and-agent-happiness]]
- [[p01-blocks-keyword-end]]
- [[base-example]]
- [[draft-example-ruby-shaped]]
- [[full-example-q1-q7]]
