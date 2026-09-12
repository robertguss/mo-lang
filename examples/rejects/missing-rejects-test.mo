module Rejects.MissingRejectsTest
expose abs

intent "A requires without a rejects test is a compile error."
# expect error: every requires must have a test rejects that trips it

fn abs(n: Int32) : Int32
  requires n >= 0

  n
end

test "positive passes"
  assert abs(3) == 3
end
