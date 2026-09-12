module Rejects.Rebinding
expose advance
intent "An immutable binding cannot be rebound."
# expect error: The immutable name count is bound a second time.

fn advance(start: UInt32) : UInt32
  count = start
  count = count + 1
  count
end

test "the body is rejected before this assertion can run"
  assert advance(2) == 3
  assert advance(0) == 1
end
