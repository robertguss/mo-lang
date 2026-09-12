---
title: "Draft example, Ruby-shaped (superseded)"
created: 2026-09-12
updated: 2026-09-12
type: example
tags: [syntax]
sources: [raw/notion/design-journal-2026-09-12.md]
status: superseded
---

# Draft example, Ruby-shaped (superseded)

*Superseded by [[base-example]]; kept because several picks were made by reacting to it.*

```ruby
module Payments::Refund
  intent "Refund a captured charge, at most once, within 90 days of capture."

  never refund.amount > charge.captured_amount
  never a charge is refunded twice
  never card.number reaches log

  type Money = UInt64 where value <= 10_000_000_00

  struct Charge
    id              : ChargeId
    captured_amount : Money
    captured_at     : Time
    refunded        : Bool
  end

  enum RefundError
    ChargeNotFound(id : ChargeId)
    AlreadyRefunded(id : ChargeId)
    WindowExpired(captured_at : Time, now : Time)
    Timeout
  end

  def within_window?(charge : Charge, now : Time) : Bool
    requires now >= charge.captured_at

    now - charge.captured_at <= 90.days
  end

  def apply_refund(charge : Charge, amount : Money) : Result(Charge, RefundError)
    requires amount <= charge.captured_amount
    ensures  ok(c) implies c.refunded?

    return error AlreadyRefunded(charge.id) if charge.refunded?

    ok charge.with(refunded: true)
  end

  def refund(db : Ledger, clock : Clock, id : ChargeId, amount : Money) : Result(Refund, RefundError)
    requires amount > 0
    ensures  ok(r) implies r.amount == amount

    now    = clock.now
    charge = try db.find_charge(id, within: 200.ms)

    unless within_window?(charge, now)
      return error WindowExpired(captured_at: charge.captured_at, now: now)
    end

    updated = try apply_refund(charge, amount)
    try db.save_charge(updated, within: 200.ms)

    ok Refund.new(charge: id, amount: amount, at: now)
  end

  process RefundQueue
    state
      pending : List(RefundRequest) where size <= 1_000
      done    : UInt32
    end

    invariant done >= 0

    message Enqueue(request : RefundRequest)
    message Drain

    def update(state, message, db : Ledger, clock : Clock)
      case message
      when Enqueue(request)
        state.with(pending: state.pending.push(request))
      when Drain
        var done = state.done
        state.pending.each do |request|
          case refund(db, clock, request.id, request.amount)
          when Ok(_)     then done += 1
          when Error(e)  then log.warn(e)
          end
        end
        state.with(pending: [], done: done)
      end
    end
  end

  test "refund within window succeeds"
    charge = Charge.fixture(captured_at: t0, captured_amount: 5_00)
    assert apply_refund(charge, 5_00) == ok(charge.with(refunded: true))
  end

  test "second refund is rejected"
    charge = Charge.fixture(refunded: true)
    assert apply_refund(charge, 1_00) == error(AlreadyRefunded(charge.id))
  end

  test rejects "amount above captured violates requires"
    charge = Charge.fixture(captured_amount: 5_00)
    apply_refund(charge, 9_99)
  end

  verified by contracts, tests, simulation(runs: 1_000)
end
```

## Related
- [[syntax-overview]]
- [[base-example]]
