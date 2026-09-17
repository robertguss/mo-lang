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
    state.done >= old(state.done)
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

property "any valid refund leaves the charge refunded"
  for charge in any(Charge), amount in any(Money) if !charge.refunded? and amount <= charge.captured_amount
    assert charge.apply_refund(amount) is Ok(c) and c.refunded?
  end
end

verified: types, contracts, tests (5), property (200 seeds), sim (1_000 runs)
```

## The rules, one line each

- **Module:** `module A.B`, one per file, path equals file path. `use A.B{X, Y}`; a bare `use A.B` is `MO0321`; no wildcards, no aliases. Private by default. One `expose a, b, C` line directly under the module header names everything public; declarations carry no marker. The `expose` line is the spec altitude's table of contents.
- **Intent and never:** `intent "..."` once per module. `never "sentence" ... end` is a sentence plus a `for ... end` block whose body is true when the bad thing happened. `flows(T, into: Cap)` is a checkable information-flow rule.
- **Definition line:** `fn name(arg: Type) : Ret`. No space before the colon in `arg: Type`, `:` for the return type, generics in parens: `Result(Charge, RefundError)`, `List(T)`.
- **Contracts:** `requires` and `ensures` directly after the signature, a blank line, then the body. `result` is the return value, `old(x)` the entry value, `is` an inline pattern test, `implies` the connective.
- **Bindings:** `x = expr` binds once. `var x = expr` may change. Rebinding or an unused binding is an error.
- **Conditionals:** `if cond ... end`, an expression, no parens. Trailing `if` only on a one-line `return`. Where a value goes, an `if` may be one line, `if cond: a else: b`, with both branches, each one expression; a statement keeps the block form (session 5, step 25).
- **Matching:** `case v ... Pattern: expr ... end`. Arms run until the next `Pattern:` or `end`. Exhaustive; guards with `if` on the arm; nested destructuring. A one-field variant matches positionally (`Ok(c)`, `Enqueue(request)`); more fields match by name.
- **Results:** `Ok(x)`, `Error(e)`, `Some(x)`, `None`. `try expr` propagates. `x or default` for `Option`. Predicates end in `?`.
- **Types:** `struct`, `enum` with data variants, `type Money = UInt64 where value <= ...`. Construction is call-style with named fields, never positional. Change a struct only via `var copy = x` then `copy.field = v`, and a `never` cannot see the copy between the assignments (session 6, step 27).
- **Loops:** `for x in xs ... end`, `for i in 0..n ... end` (`n` excluded), `break` allowed. Every `for` closes with `end`, in a body, a `never`, or a `property` alike. A pure body is written with `map`, `filter`, or `reduce` instead (`charges.filter(fn(c) c.refunded? end)`); `for` is for bodies with effects, `try`, `break`, or `return`, like the `Drain` arm above. The formatter enforces the split.
- **Anonymous functions:** `fn(x) expr end`, call arguments only.
- **Numbers and strings:** `10_000` (typed from its uses, else `Int64`), `200.ms`, `90.days` (`Duration`, dot-call functions, extensible). `"Hello #{name}"`, double quotes only, `"""` for multi-line. No literal suffixes.
- **Process and supervisor:** as in the example. `state` (fields start at their type's zero, or write `= expr`), `invariant` (the condition that holds after every `update`), `message`, `update`. `mailbox: N` in the header. A supervisor takes the capabilities its children need and passes them on each `child` line.
- **Tests:** same file, under the code. `test "sentence"`, `test rejects "sentence"`, `property "sentence"` with `any(Type)`.
- **`verified:` line:** at the bottom, computed by the toolchain, a compile error to edit by hand.
- **Recipes:** `recipe Name ... end`, chapter 6.

## Session 4 changes

The example and rules above already reflect these; this section is the record of what changed and why.

Robert (session 4): `pub` has OOP vibes. **In** on the Elm-style `expose` line: privacy by default, one line under `module` lists the public names, no marker on any declaration. Every `pub` in these chapters, `grammar.md`, and pick 14 now reads as "named on the `expose` line".

Robert (session 4): `use A.B{X, Y}`, no dot before the braces. Applied here, in `grammar.md`, and in pick 14.

Robert (session 4): the comprehension `for` inside `never` and `property` had no `end`, which looked like whitespace sensitivity. Every `for` now closes with `end`. Robert also asked whether `for` should go entirely in favour of `map`/`filter`/`reduce`; **in** on keeping both with one rule: pure bodies use the combinators, `for` is only for effects, `try`, `break`, or `return`, and the formatter enforces it. First tested by the `examples/` corpus.

## Session 5 changes

The example and rules above already reflect these; this section is the changelog.

Claude (session 5, deciding on Robert's instruction to build first): the supervisor takes parameters and passes them on the `child` line, the one addition of syntax; one-field variants match positionally; `a..b` excludes `b`; `state` fields start at zero; literals are typed from use. The three-worker corpus (`examples/`, `plans/model-bakeoff.md`) found every one of these; the full list with what tests each is at the foot of `grammar.md`.

Claude (session 5, from the interpreter): the example broke its own law. `within_window?` and `refund` each have a `requires` with no `test rejects`, and `mo check` refused the file with `MO0311`. Two `rejects` tests added; the `verified:` line counts 5 (the corpus file `examples/payments/refund.mo` has since grown to seven tests, four of them `rejects`, and its line says so; the example above shows four). The compiler reviewing the spec is the point of the milestone.

Claude (session 5, from the interpreter, second pass): three more corrections the toolchain forced on the example. `result` is a keyword, so the first test binds `outcome`. The property was false: `any(Charge)` generates refunded charges, which `apply_refund` rightly refuses, so the guard gains `!charge.refunded?`. `RefundQueue` gains `message Done : UInt32` so a test can `ask` for the count; the corpus copy at `examples/payments/refund.mo` carries that test. Chapter 4 now compiles and runs as written, minus the `verified:` line, which the toolchain prints.

Session 5, step 18: the example's `invariant` body reads `state.done >= old(state.done)`, the condition that holds, not the one that breaks it.
