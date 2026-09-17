---
title: "Two altitudes in one language"
created: 2026-09-12
updated: 2026-09-17
type: deep-dive
tags: [philosophy, contracts]
sources: [raw/notion/design-journal-2026-09-12.md]
---

# Two altitudes in one language

- **Spec altitude** (what humans read): module and function signatures, contracts (`requires` / `ensures`), effect declarations, an `intent` statement per unit, and a visible verification level (`verified by tests, contracts` vs `proof`). Semantically binding, not comments. Reads like a design doc.
- **Implementation altitude** (what agents write): function bodies, checked against the spec altitude, collapsed by default.
Sketch (the 12 Sep sketch, pre-pick syntax; noted 17 Sep 2026):
```ruby
module payments.refund

intent "Refund a captured charge, at most once, within 90 days of capture."

fn refund(charge: Charge, amount: Money) -> Result<Refund, RefundError>
  requires amount <= charge.captured_amount
  requires charge.captured_at within 90.days
  ensures  result.ok implies ledger.balance == old(ledger.balance) - amount
  effects  db.write(ledger), net.call(stripe)
  verified by tests, contracts
```

## Related
- [[d02-spec-altitude]]
- [[p08-contracts]]
