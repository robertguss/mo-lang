module Basics.For
expose first_over, boxes_that_fit

intent "Loop with for only when the body returns or breaks early; a pure body uses map, filter, or reduce."

fn first_over(prices: List(UInt32), limit: UInt32) : Option(UInt32)
  for price in prices
    return Some(price) if price > limit
  end
  None
end

fn boxes_that_fit(box: UInt32, capacity: UInt32) : UInt32
  var packed = 0
  # break is why this is a for: reduce cannot stop at the first box that does not fit
  for n in 1..100
    if n * box > capacity
      break
    end
    packed = n
  end
  packed
end

test "return leaves the loop at the first match"
  assert first_over([3, 12, 40], 10) is Some(12)
  assert first_over([3, 4], 10) is None
end

test "break stops the range early"
  assert boxes_that_fit(30, 100) == 3
end

verified: types, contracts, tests (2), property (0 seeds), sim (not run)
          proven: not run
