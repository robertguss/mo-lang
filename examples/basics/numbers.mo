module Basics.Numbers
expose add_stock, remove_stock, scramble, average

intent "Size every integer, and name what should happen at its edge instead of crashing."

fn add_stock(count: UInt16, more: UInt16) : Option(UInt16)
  count.checked_add(more)
end

fn remove_stock(count: UInt16, less: UInt16) : UInt16
  count.saturating_sub(less)
end

fn scramble(hash: UInt32) : UInt32
  hash.wrapping_mul(2_654_435_761)
end

fn average(total: Float64, count: Float64) : Float64
  total / count
end

test "adding past the top is None, not a crash"
  assert add_stock(10, 5) is Some(15)
  assert add_stock(65_000, 10_000) is None
end

test "removing past zero stops at zero"
  assert remove_stock(3, 10) == 0
end

test "multiplication wraps when asked to"
  assert scramble(2) == 1_013_904_226
end

test "floats divide without rounding"
  assert average(10.0, 4.0) == 2.5
end

verified: types, contracts, tests (4), property (0 seeds), sim (not run)
          proven: not run
