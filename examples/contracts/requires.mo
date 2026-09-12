module Contracts.Requires
expose half
intent "Pair a precondition with a test that deliberately violates it."

fn half(n: UInt32) : UInt32
  requires n % 2 == 0

  n / 2
end

test "an even input satisfies the precondition"
  assert half(8) == 4
end

test rejects "an odd input violates the precondition"
  half(3)
end
