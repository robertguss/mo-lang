# 4. Syntax

Ruby's look with Go's discipline. Every block opens with a keyword and closes with `end`. No braces, no `def`, no `->`, no `::`, no `do |x|`, no `unless`, no ternary. `#` is the only comment. One way to write everything.

The refund module is the running example. Read it top to bottom; the sections after it name each rule.

```ruby
module Payments.Refund
expose Refund, RefundError, apply_refund, refund, RefundQueue

use Payments.Ledger{Charge, ChargeId, Money}

intent "Refund a captured charge, at most once, within 90 days of capture."

never "a refund exceeds its charge"
  for r in Refund.all, c in Charge.all if r.charge == c.id
    r.amount > c.captured_amount
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

supervisor Payments
  child RefundQueue, restart: :always, max_restarts: 5 per 1.minute
end

test "refund within window succeeds"
  charge = Charge.fixture(captured_at: t0, captured_amount: Money.cents(500))
  result = charge.apply_refund(Money.cents(500))
  assert result is Ok(c)
  assert c.refunded?
end

test rejects "amount above captured"
  charge = Charge.fixture(captured_amount: Money.cents(500))
  charge.apply_refund(Money.cents(999))
end

property "any valid refund leaves the charge refunded"
  for charge in any(Charge), amount in any(Money) if amount <= charge.captured_amount
    assert charge.apply_refund(amount) is Ok(c) and c.refunded?
end

verified: types, contracts, tests (3), property (200 seeds), sim (1_000 runs)
```

## The rules, one line each

- **Module:** `module A.B`, one per file, path equals file path. `use A.B` or `use A.B{X, Y}`; no wildcards, no aliases. Private by default. One `expose a, b, C` line directly under the module header names everything public; declarations carry no marker. The `expose` line is the spec altitude's table of contents.
- **Intent and never:** `intent "..."` once per module. `never "sentence" ... end` is a sentence plus a block that is true when the bad thing happened. `flows(T, into: Cap)` is a checkable information-flow rule.
- **Definition line:** `fn name(arg: Type) : Ret`. No space before the colon in `arg: Type`, `:` for the return type, generics in parens: `Result(Charge, RefundError)`, `List(T)`.
- **Contracts:** `requires` and `ensures` directly after the signature, a blank line, then the body. `result` is the return value, `old(x)` the entry value, `is` an inline pattern test, `implies` the connective.
- **Bindings:** `x = expr` binds once. `var x = expr` may change. Rebinding or an unused binding is an error.
- **Conditionals:** `if cond ... end`, an expression, no parens. Trailing `if` only on a one-line `return`.
- **Matching:** `case v ... Pattern: expr ... end`. Arms run until the next `Pattern:` or `end`. Exhaustive; guards with `if` on the arm; nested destructuring.
- **Results:** `Ok(x)`, `Error(e)`, `Some(x)`, `None`. `try expr` propagates. `x or default` for `Option`. Predicates end in `?`.
- **Types:** `struct`, `enum` with data variants, `type Money = UInt64 where value <= ...`. Construction is call-style with named fields, never positional. Change a struct only via `var copy = x` then `copy.field = v`.
- **Loops:** `for x in xs ... end`, `for i in 0..n ... end`, `break` allowed. Nothing else.
- **Anonymous functions:** `fn(x) expr end`, call arguments only.
- **Numbers and strings:** `10_000`, `200.ms`, `90.days` (dot-call functions, extensible). `"Hello #{name}"`, double quotes only, `"""` for multi-line. No literal suffixes.
- **Process and supervisor:** as in the example. `state`, `invariant`, `message`, `update`. `mailbox: N` in the header.
- **Tests:** same file, under the code. `test "sentence"`, `test rejects "sentence"`, `property "sentence"` with `any(Type)`.
- **`verified:` line:** at the bottom, computed by the toolchain, a compile error to edit by hand.
- **Recipes:** `recipe Name ... end`, chapter 6.

## Session 4 note

Robert (session 4): `pub` has OOP vibes. **In** on the Elm-style `expose` line: privacy by default, one line under `module` lists the public names, no marker on any declaration. Every `pub` in these chapters, `grammar.md`, and pick 14 now reads as "named on the `expose` line".

Robert (session 4): `use A.B{X, Y}`, no dot before the braces. Applied here, in `grammar.md`, and in pick 14.
