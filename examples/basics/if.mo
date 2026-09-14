module Basics.If
expose shipping, note, label

intent "Branch with if as a statement, as a value in block form and on one line, and as a one-line guard on return."

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

fn label(count: UInt32) : String
  word = if count == 1: "line" else: "lines"
  "#{count} #{word}, #{if count > 99: "long" else: if count > 9: "medium" else: "short"}"
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

test "a one-line if gives a value"
  assert label(1) == "1 line, short"
  assert label(12) == "12 lines, medium"
  assert label(100) == "100 lines, long"
end

verified: types, contracts, tests (4), property (0 seeds), sim (not run)
          proven: not run
