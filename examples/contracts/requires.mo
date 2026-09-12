module Contracts.Requires
expose abs

intent "Every requires has a rejects test that trips it."

fn abs(n: Int32) : Int32
  requires n >= 0

  n
end

test "non-negative passes"
  assert abs(3) == 3
end

test rejects "a negative trips requires"
  abs(-1)
end
