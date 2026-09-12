module Rejects.SevenParameters
expose sum
intent "A function may have at most six parameters."
# expect error: The sum function declares seven parameters.

fn sum(a: UInt32, b: UInt32, c: UInt32, d: UInt32, e: UInt32, f: UInt32, g: UInt32) : UInt32
  left = a + b + c
  right = d + e + f
  left + right + g
end

test "using every parameter does not lift the limit"
  assert sum(1, 1, 1, 1, 1, 1, 1) == 7
  assert sum(0, 0, 0, 0, 0, 0, 0) == 0
end
