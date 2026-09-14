module Rejects.NoImplicitConversion
expose half

intent "Mo has no implicit conversion: a UInt32 is not a UInt64 until a named conversion makes it one."

# expect MO0206: expected UInt64, found UInt32
fn half(n: UInt32) : UInt64
  n / 2
end

test "half of ten is five"
  assert half(10) == 5
end
