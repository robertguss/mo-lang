module Rejects.UnusedBinding
expose total

intent "Every binding is read; a name that is bound and never used does not compile."
# expect MO0307: discount is bound but never used.

fn total(price: UInt32, tax: UInt32) : UInt32
  discount = price / 10
  sum = price + tax
  sum
end

test "tax is added"
  assert total(100, 10) == 110
  assert total(0, 0) == 0
end
