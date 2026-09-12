module Basics.Numbers
expose sample

intent "Sized ints, 10_000, named overflow ops, and a float."

fn sample() : (UInt32, UInt32, UInt32, UInt32, Float64)
  n = 10_000
  a = n.checked_add(1) or 0
  b = n.saturating_sub(1)
  c = n.wrapping_mul(2)
  f = 1.5
  (n, a, b, c, f)
end

test "underscores, named overflow, and a float"
  t = sample()
  assert t.0 == 10_000
  assert t.1 == 10_001
  assert t.2 == 9_999
  assert t.3 == 20_000
  assert t.4 == 1.5
end
