module Basics.ReturnsNothing
expose Reading, describe, report

intent "A function called only for what it writes leaves its return type off, as main does, and a negative number is a pattern."

enum Reading
  Degrees(value: Int64)
  Unread
end

# A reading in words; minus forty is where both scales meet.
fn describe(reading: Reading) : String
  case reading
    Degrees(-40): "minus forty, on both scales"
    Degrees(0): "freezing"
    Degrees(value) if value < 0: "below freezing"
    Degrees(_): "above freezing"
    Unread: "no reading"
  end
end

# Writes each reading's words on a line of its own, and gives nothing back.
fn report(out: Out, readings: List(Reading))
  for reading in readings
    out.write_line(describe(reading))
  end
end

test "a negative number matches in a pattern"
  assert describe(Degrees(value: -40)) == "minus forty, on both scales"
  assert describe(Degrees(value: -3)) == "below freezing"
  assert describe(Degrees(value: 0)) == "freezing"
  assert describe(Degrees(value: 7)) == "above freezing"
  assert Degrees(value: -40) is Degrees(-40)
end

test "a function that returns nothing is called for what it does"
  out = Out.fixture()
  report(out, [Degrees(value: -40), Unread])
  assert out.written == ["minus forty, on both scales\n", "no reading\n"]
end

verified: types, contracts, tests (2), property (0 seeds), sim (not run)
          proven: not run
