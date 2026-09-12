module Rejects.MissingRejectsTest
expose half
intent "A requires clause must have a rejects test that trips it."
# expect error: The requires clause has no matching rejects test.

fn half(n: UInt32) : UInt32
  requires n % 2 == 0

  n / 2
end

test "passing inputs do not replace a rejects test"
  assert half(4) == 2
  assert half(0) == 0
end
