---
title: "Syntax pick 7: Types"
created: 2026-09-12
updated: 2026-09-12
type: syntax-pick
tags: [syntax, types]
sources: [raw/notion/design-journal-2026-09-12.md]
number: 7
status: liked
chosen_by: Robert
---

# Syntax pick 7: Types

`struct Charge ... end` with `id: ChargeId` lines, `enum RefundError ... end` with `WindowExpired(captured_at: Time, now: Time)` variants, refinements `type Money = UInt64 where value <= ...`. Construction is call-style with named fields, `Charge(id: id, ...)`, identical for structs and enum variants; never positional. Every field required unless `Option`. **`.with` removed** (Robert). The only way to change a struct anywhere: `var updated = charge` then `updated.refunded = true`.

## Related
- [[d22-rust-plus-refinements-types]]
- [[base-example]]
