module Basics.If
expose label, count
intent "Use if as a statement, an expression, and a return guard."

fn label(n: UInt32) : String
  return "zero" if n == 0
  word = if n == 1
    "one"
  else
    "many"
  end
  word
end

fn count(ready: Bool) : UInt32
  var n = 0
  if ready
    n += 1
  end
  n
end

test "each conditional form chooses a branch"
  assert label(0) == "zero"
  assert label(1) == "one"
  assert label(2) == "many"
  assert count(true) == 1
  assert count(false) == 0
end
