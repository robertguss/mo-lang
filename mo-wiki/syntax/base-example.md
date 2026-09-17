---
title: "Current base example (Robert's style)"
created: 2026-09-12
updated: 2026-09-17
type: example
tags: [syntax]
sources: [raw/notion/design-journal-2026-09-12.md, raw/notion/open-questions-2026-09-12.md]
---

# Current base example (Robert's style)

```ruby
module Payments.Refund

intent "Refund a captured charge, at most once, within 90 days of capture."

never "a refund exceeds its charge"
  for r in Refund.all, c in Charge.all if r.charge == c.id
    r.amount > c.captured_amount
  end
end

struct Charge
  id: ChargeId
  captured_amount: Money
  captured_at: Time
  refunded: Bool
end

enum RefundError
  AlreadyRefunded(id: ChargeId)
  WindowExpired(captured_at: Time, now: Time)
  Timeout
end

fn apply_refund(charge: Charge, amount: Money) : Result(Charge, RefundError)
  requires amount <= charge.captured_amount

  return Error(AlreadyRefunded(charge.id)) if charge.refunded?

  var updated = charge
  updated.refunded = true
  Ok(updated)
end

fn refund(db: Ledger, clock: Clock, id: ChargeId, amount: Money) : Result(Refund, RefundError)
  requires amount > 0

  now = clock.now
  charge = try db.find_charge(id, within: 200.ms)

  if !within_window?(charge, now)
    return Error(WindowExpired(captured_at: charge.captured_at, now: now))
  end

  updated = try apply_refund(charge, amount)
  try db.save_charge(updated, within: 200.ms)

  Ok(Refund(charge: id, amount: amount, at: now))
end

process Counter
  state
    count: UInt32
  end

  message Increment
  message Reset

  fn update(state, message)
    case message
      Increment: state.count += 1
      Reset: state.count = 0
    end
  end
end

test "second refund is rejected"
  charge = Charge.fixture(refunded: true)
  assert apply_refund(charge, 1_00) == Error(AlreadyRefunded(charge.id))
end
```
*The older Ruby-shaped draft, [[draft-example-ruby-shaped]], is superseded by this base. Session 4 closed the comprehension `for` with `end` (pick 11); applied here 17 Sep 2026.*

## Related
- [[syntax-overview]]
- [[q07-process-api]]
- [[full-example-q1-q7]]
