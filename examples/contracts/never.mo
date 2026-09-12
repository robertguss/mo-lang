module Contracts.Never
expose Refund, Charge, amount_of

intent "A never is a sentence plus a two-generator comprehension with a guard."

struct Refund
  charge: UInt32
  amount: UInt32
end

struct Charge
  id: UInt32
  captured: UInt32
end

never "a refund exceeds its charge"
  for r in Refund.all, c in Charge.all if r.charge == c.id
    r.amount > c.captured
  end
end

fn amount_of(r: Refund) : UInt32
  r.amount
end

test "amount is the struct field"
  r = Refund(charge: 1, amount: 5)
  assert amount_of(r) == 5
end
