module Basics.For
expose contains?, stop_at
intent "Use finite loops when return or break can end traversal early."

fn contains?(xs: List(UInt32), wanted: UInt32) : Bool
  for x in xs
    return true if x == wanted
  end
  false
end

fn stop_at(limit: UInt32) : UInt32
  var last = 0
  for i in 0..10
    if i == limit
      break
    end
    last = i
  end
  last
end

test "return and break end finite loops"
  assert contains?([2, 4], 4)
  assert !contains?([], 4)
  assert stop_at(3) == 2
  assert stop_at(0) == 0
end
