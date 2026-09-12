module Rejects.SevenParameters
expose sum7

intent "At most six parameters; beyond that, a struct."
# expect error: a function may have at most six parameters

fn sum7(a: UInt32, b: UInt32, c: UInt32, d: UInt32, e: UInt32, f: UInt32, g: UInt32) : UInt32
  a + b + c + d + e + f + g
end

test "never reached"
  assert sum7(1, 1, 1, 1, 1, 1, 1) == 7
end
