module Basics.Numbers
expose total, fraction
intent "Use sized numbers and name arithmetic that does not trap."

fn total(n: UInt32) : Option(UInt32)
  n.checked_add(10_000)
end

fn fraction() : Float64
  0.5
end

test "named arithmetic states the overflow policy"
  n = 2
  assert (total(n) or 0) == 10_002
  assert n.saturating_sub(3) == 0
  assert n.wrapping_mul(3) == 6
  assert fraction() == 0.5
end
