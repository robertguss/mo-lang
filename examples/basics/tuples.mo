module Basics.Tuples
expose pair, sum
intent "Build a tuple, select a field, and destructure both fields."

fn pair(n: UInt32) : (UInt32, UInt32)
  (n, n + 1)
end

fn sum(values: (UInt32, UInt32)) : UInt32
  case values
    (left, right): left + right
  end
end

test "tuple fields keep their order"
  values = pair(3)
  assert values.0 == 3
  assert values.1 == 4
  assert sum(values) == 7
end
