---
title: "Syntax pick 14: Modules"
created: 2026-09-12
updated: 2026-09-12
type: syntax-pick
tags: [syntax]
sources: [raw/notion/design-journal-2026-09-12.md]
number: 14
status: liked
chosen_by: Robert
---

# Syntax pick 14: Modules

private by default, `pub` to expose (the `pub` lines are the spec altitude's table of contents). One `use` form: `use Payments.Ledger` or `use Payments.Ledger.{Charge, Money}`; no wildcards, no aliases, no relative or file paths. One module per file; file path equals module path (`payments/refund.mo`). No cycles; the compiler names the cycle. Any change to a `pub` signature or contract is a breaking version change, decided by the toolchain. Elixir's four keywords (`alias`/`import`/`require`/`use`) collapsed to one.

## Session 4 note

Robert: `pub` has OOP vibes. Claude recommended an Elm-style `expose` line; Robert **in**. Private by default, no marker on declarations:

```ruby
module Payments.Refund
expose Refund, RefundError, apply_refund, refund, RefundQueue
```

The `expose` line is now the spec altitude's table of contents; a breaking change is a diff to that line or to an exposed signature. Alternatives not taken: a Ruby `private` section (implicit API, reordering changes it) and renaming to `export` (still a per-declaration marker).

Robert (session 4): the `use` list drops the dot: `use Payments.Ledger{Charge, Money}`.

## Related
- [[p09-module-header-and-never]]
- [[q17-package-management-and-supply-chain]]
