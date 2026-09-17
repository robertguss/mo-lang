---
title: "Full example with Q1–Q7 applied"
created: 2026-09-12
updated: 2026-09-17
type: example
tags: [syntax]
sources: [raw/notion/open-questions-2026-09-12.md]
---

# Full example with Q1–Q7 applied

This is the base with every pick applied, including [[q01-comments|Q1]]–[[q07-process-api|Q7]] above. Read it top to bottom and note anything that bothers you. Brought to the current forms 17 Sep 2026: the `expose` line for `pub` (session 4, pick 14), every comprehension `for` closed with `end` (session 4, pick 11), the positive `invariant` (session 5, step 18), and the property's `!charge.refunded?` guard (chapter 4's note). Chapter 4 holds the same module as the spec's running thread.
```ruby
module Payments.Refund
expose Refund, RefundError, apply_refund, refund, RefundQueue

use Payments.Ledger{Charge, ChargeId, Money}

intent "Refund a captured charge, at most once, within 90 days of capture."

never "a refund exceeds its charge"
  for r in Refund.all, c in Charge.all if r.charge == c.id
    r.amount > c.captured_amount
  end
end

never "a card number reaches an event"
  flows(CardNumber, into: Events)
end

# A refund that has been applied to a charge.
struct Refund
  charge: ChargeId
  amount: Money
  at: Time
end

enum RefundError
  AlreadyRefunded(id: ChargeId)
  WindowExpired(captured_at: Time, now: Time)
  Timeout
end

fn within_window?(charge: Charge, now: Time) : Bool
  requires now >= charge.captured_at

  now - charge.captured_at <= 90.days
end

fn apply_refund(charge: Charge, amount: Money) : Result(Charge, RefundError)
  requires amount <= charge.captured_amount
  ensures  result is Ok(c) implies c.refunded?

  return Error(AlreadyRefunded(id: charge.id)) if charge.refunded?

  var updated = charge
  updated.refunded = true
  Ok(updated)
end

fn refund(db: Ledger, clock: Clock, id: ChargeId, amount: Money) : Result(Refund, RefundError)
  requires amount > Money.zero
  ensures  result is Ok(r) implies r.amount == amount

  now = clock.now
  charge = try db.find_charge(id, within: 200.ms)

  if !charge.within_window?(now)
    return Error(WindowExpired(captured_at: charge.captured_at, now: now))
  end

  updated = try charge.apply_refund(amount)
  try db.save_charge(updated, within: 200.ms)

  Ok(Refund(charge: id, amount: amount, at: now))
end

process RefundQueue(db: Ledger, clock: Clock, events: Events)
  state
    pending: List(RefundRequest) where size <= 1_000
    done: UInt32
  end

  invariant "done never goes backwards"
    state.done >= old(state.done)
  end

  message Enqueue(request: RefundRequest)
  message Drain

  fn update(state, message)
    case message
      Enqueue(request):
        state.pending = state.pending.push(request)
      Drain:
        for request in state.pending
          case refund(db, clock, request.id, request.amount)
            Ok(r): events.emit(RefundCompleted(refund: r))
            Error(e): events.emit(RefundFailed(request: request, reason: e))
          end
        end
        state.pending = []
        state.done += 1
    end
  end
end

test "refund within window succeeds"
  charge = Charge.fixture(captured_at: t0, captured_amount: Money.cents(500))
  result = charge.apply_refund(Money.cents(500))
  assert result is Ok(c)
  assert c.refunded?
end

test "second refund is rejected"
  charge = Charge.fixture(refunded: true)
  assert charge.apply_refund(Money.cents(100)) == Error(AlreadyRefunded(id: charge.id))
end

test rejects "amount above captured"
  charge = Charge.fixture(captured_amount: Money.cents(500))
  charge.apply_refund(Money.cents(999))
end

property "any valid refund leaves the charge refunded"
  for charge in any(Charge), amount in any(Money) if !charge.refunded? and amount <= charge.captured_amount
    assert charge.apply_refund(amount) is Ok(c) and c.refunded?
  end
end

verified: contracts, tests, simulation(1_000 runs)
```

## Related
- [[base-example]]
- [[syntax-overview]]
- [[p14-modules]], [[p11-loops-and-anonymous-functions]], [[p10-process]]

