module Basics.Bindings
expose advance
intent "Bind a starting value once and change a local counter."

fn advance(start: UInt32) : UInt32
  step = 2
  var count = start
  count += step
  count -= 1
  count
end

test "advance keeps the original value"
  start = 4
  assert advance(start) == 5
  assert start == 4
end
