module Contracts.Never
expose Refund, Charge
intent "Forbid a refund larger than the matching charge."

never "a refund exceeds its charge"
  for r in Refund.all, c in Charge.all if r.charge == c.id
    r.amount > c.amount
  end
end

struct Refund
  charge: UInt32
  amount: UInt32
end

struct Charge
  id: UInt32
  amount: UInt32
end

test "matching values stay below the forbidden boundary"
  charge = Charge(id: 1, amount: 5)
  refund = Refund(charge: 1, amount: 4)
  assert refund.charge == charge.id
  assert refund.amount <= charge.amount
end
