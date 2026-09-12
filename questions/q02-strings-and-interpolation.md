---
title: "Q2: Strings and interpolation"
created: 2026-09-12
updated: 2026-09-12
type: question
tags: [syntax]
sources: [raw/notion/open-questions-2026-09-12.md]
number: 2
status: answered
answer: in
asked: 2026-09-12
---

# Q2: Strings and interpolation

**Options:** Ruby `"Hello #{name}"` / Python `f"Hello {name}"` / Rust `format!("Hello {name}")`.
**Recommendation:** Ruby's `"Hello #{name}"`. Double quotes only. Multi-line strings with triple quotes `""" ... """`. No single-quoted strings, no heredocs, no raw-string variants.
**Why:** Ruby's form is the most-read interpolation syntax alive, and Elixir uses it too. Removing single quotes removes a choice agents don't need. Strings are UTF-8 always; `String.length` is grapheme count, `String.bytes` is bytes, so the ambiguity that bites every language is a named choice at the call site.
✅ **Robert: IN** (session 2). Also settled: every string interpolates (no prefix to forget), triple-quoted literals strip common leading indentation, no raw-string form — regex is a compiled Regex value, not a bare string.

## Related
- [[q03-numbers-and-units]]
- [[d27-simple-and-elegant-like-ruby]]
