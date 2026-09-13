module Basics.If
expose shipping, note

intent "Branch with if as a statement, as a value, and as a one-line guard on return."

fn shipping(total: UInt32, express: Bool) : UInt32
  return 0 if total >= 5_000

  var cost = 500
  if express
    cost += 1_000
  end
  cost
end

fn note(total: UInt32) : String
  missing = if total >= 5_000
    0
  else
    5_000 - total
  end
  "#{missing} cents to free shipping"
end

test "large orders ship free"
  assert shipping(6_000, true) == 0
end

test "express costs more"
  assert shipping(1_000, false) == 500
  assert shipping(1_000, true) == 1_500
end

test "if gives a value"
  assert note(4_000) == "1000 cents to free shipping"
  assert note(9_000) == "0 cents to free shipping"
end
