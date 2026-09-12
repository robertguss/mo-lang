---
title: "Direction 22: Type system: Rust-plus-refinements from day one"
created: 2026-09-12
updated: 2026-09-12
type: direction
tags: [types, contracts]
sources: [raw/notion/design-journal-2026-09-12.md]
number: 22
status: liked
origin: "Robert"
---

# Direction 22: Type system: Rust-plus-refinements from day one

Traits (without the deep solver machinery), enums with data, generics with bounds, exhaustive matching, plus refinement types on primitives (`Money where value >= 0`) discharged statically when provable and at runtime otherwise. This is where `never` clauses can become types. Dependent types rejected: models write them at ~27% success vs ~82% for contract-style. (Robert)

## Related
- [[d11-statically-typed]]
- [[p07-types-struct-enum-refinement]]
