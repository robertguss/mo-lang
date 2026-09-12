module Rejects.DefaultParameter
expose advance
intent "Every parameter is required at the call site."
# expect error: A parameter cannot declare a default value.

fn advance(n: UInt32, step: UInt32 = 1) : UInt32
  n + step
end

test "explicit calls do not make a default declaration legal"
  assert advance(2, 1) == 3
  assert advance(0, 2) == 2
  assert advance(4, 0) == 4
  assert advance(1, 1) == 2
end
