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
  ensures result is Ok(c) implies c.refunded?

  return Error(AlreadyRefunded(id: charge.id)) if charge.refunded?

  var updated = charge
  updated.refunded = true
  Ok(updated)
end

fn refund(db: Ledger, clock: Clock, id: ChargeId, amount: Money) : Result(Refund, RefundError)
  requires amount > Money.zero
  ensures result is Ok(r) implies r.amount == amount

  now = clock.now
  charge = try db.find_charge(id, within: 200.ms)

  if !charge.within_window?(now)
    return Error(WindowExpired(captured_at: charge.captured_at, now: now))
  end

  updated = try charge.apply_refund(amount)
  try db.save_charge(updated, within: 200.ms)

  Ok(Refund(charge: id, amount: amount, at: now))
end

process RefundQueue(db: Ledger, clock: Clock, events: Events) mailbox: 10_000
  state
    pending: List(RefundRequest) where size <= 1_000
    done: UInt32
  end

  invariant "done never goes backwards"
    state.done < old(state.done)
  end

  message Enqueue(request: RefundRequest)
  message Drain
  message Done : UInt32

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
      Done: state.done
    end
  end
end

supervisor Payments(db: Ledger, clock: Clock, events: Events)
  child RefundQueue(db, clock, events), restart: :always, max_restarts: 5 per 1.minute
end

test "refund within window succeeds"
  charge = Charge.fixture(captured_at: t0, captured_amount: Money.cents(500))
  outcome = charge.apply_refund(Money.cents(500))
  assert outcome is Ok(c)
  assert c.refunded?
end

test rejects "amount above captured"
  charge = Charge.fixture(captured_amount: Money.cents(500))
  charge.apply_refund(Money.cents(999))
end

test rejects "a refund of nothing"
  refund(Ledger.fixture(), Clock.fixture(), "ch_1", Money.zero)
end

test rejects "a window read before the capture"
  charge = Charge.fixture(captured_at: t0, captured_amount: Money.cents(500))
  charge.within_window?(t0 - 1.minute)
end

test "a drained queue counts the drain"
  queue = RefundQueue.start(Ledger.fixture(), Clock.fixture(), Events.fixture())
  queue.send(Enqueue(request: RefundRequest(id: "ch_1", amount: Money.cents(500))))
  queue.send(Enqueue(request: RefundRequest(id: "ch_2", amount: Money.cents(250))))
  queue.send(Drain)
  assert queue.ask(Done, within: 1_000.ms) is Ok(1)
end

property "any valid refund leaves the charge refunded"
  for charge in any(Charge), amount in any(Money) if !charge.refunded? and amount <= charge.captured_amount
    assert charge.apply_refund(amount) is Ok(c) and c.refunded?
  end
end
