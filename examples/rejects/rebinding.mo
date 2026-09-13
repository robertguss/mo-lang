module Rejects.Rebinding
expose total

intent "A name bound with = is bound once; binding it again in the same scope does not compile."
# expect MO0306: base is bound twice in one scope; make it var base, or pick a new name.

fn total(price: UInt32, tax: UInt32) : UInt32
  base = price
  base = base + tax
  base
end

test "tax is added"
  assert total(100, 10) == 110
  assert total(0, 0) == 0
end
