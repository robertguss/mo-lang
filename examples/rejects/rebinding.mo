module Rejects.Rebinding
expose once

intent "A name binds once per scope; rebinding is an error."
# expect error: rebinding x is a compile error

fn once() : UInt32
  x = 1
  x = 2
  x
end

test "never reached"
  assert once() == 1
end
