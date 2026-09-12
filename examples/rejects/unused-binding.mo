module Rejects.UnusedBinding
expose once

intent "An unused binding is a compile error."
# expect error: unused binding x is a compile error

fn once() : UInt32
  x = 1
  2
end

test "never reached"
  assert once() == 2
end
