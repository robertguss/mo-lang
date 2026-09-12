---
title: "Syntax pick 12: Tests"
created: 2026-09-12
updated: 2026-09-12
type: syntax-pick
tags: [syntax, verification]
sources: [raw/notion/design-journal-2026-09-12.md]
number: 12
status: liked
chosen_by: Robert
---

# Syntax pick 12: Tests

in the same file as the code, under it. No test directory, no framework, no imports. `test "sentence" ... end` positive-space with one property per `assert`; `test rejects "sentence" ... end` passes only if the body trips a contract (how the compiler proves every `requires` fires); `property "sentence"` with `any(Type)` generators run under many seeds by the simulator. Sentence names, not identifiers. Precedents: Zig's `test "name"` blocks (TigerBeetle is written this way), Pyret's `where:` blocks attached to functions, D `unittest`, Rust `mod tests` + doctests, Elixir doctests, Unison hash-cached tests. Nobody combines same-file + compiler-required + `rejects` + hash caching.

## Related
- [[q08-verification-tiers]]
- [[base-example]]
