module Basics.If
expose shipping, note, label, plural, sizes, sign

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
    short = 5_000 - total
    short
  end
  "#{missing} cents to free shipping"
end

fn label(count: UInt32) : String
  word = if count == 1: "line" else: "lines"
  "#{count} #{word}, #{if count > 99: "long" else: if count > 9: "medium" else: "short"}"
end

# A one-line if as an anonymous function's body, as a call's argument, and as an arm's value.
fn plural(counts: List(UInt32)) : List(String)
  counts.map(fn(n) if n == 1: "one" else: "many" end)
end

fn sizes(total: Option(UInt32), express: Bool) : String
  case total
    Some(n): "#{label(if n == 0: 1 else: n)}, #{if n >= 5_000: "large" else: "small"}"
    None: if express: "none yet" else: "none"
  end
end

# A one-line if as a function's whole body: a body's last line is its value, as a block if's is.
fn sign(n: Int32) : String
  if n < 0: "negative" else: "not negative"
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

test "a one-line if is a value wherever a value goes"
  assert plural([1, 2]) == ["one", "many"]
  assert sizes(Some(6_000), false) == "6000 lines, long, large"
  assert sizes(Some(0), false) == "1 line, short, small"
  assert sizes(None, true) == "none yet" and sizes(None, false) == "none"
end

test "a one-line if on a body's last line is the body's value"
  assert sign(-1) == "negative"
  assert sign(0) == "not negative"
end

verified: types, contracts, tests (6), property (0 seeds), sim (not run)
          proven: not run
