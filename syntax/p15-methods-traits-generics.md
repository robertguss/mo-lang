---
title: "Syntax pick 15: Methods without objects, traits, generics"
created: 2026-09-12
updated: 2026-09-12
type: syntax-pick
tags: [syntax, types]
sources: [raw/notion/design-journal-2026-09-12.md]
number: 15
status: liked
chosen_by: Robert
---

# Syntax pick 15: Methods without objects, traits, generics

dot calls are sugar for first-argument functions (`charge.within_window?(now)` is `within_window?(charge, now)`), uniform function call syntax as in Nim and D. No methods, no `self`, no classes. `trait Comparable ... end` lists functions a type promises; `impl Comparable for Money ... end` provides them. No inheritance, no overriding defaults, no trait objects in v1. Generics only via `where`: `fn largest(items: List(T)) : Option(T) where T: Comparable`.

## Related
- [[d06-never-oop]]
- [[d22-rust-plus-refinements-types]]
