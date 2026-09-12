module Rejects.UnusedBinding
expose keep
intent "Every local binding must be consumed."
# expect error: The local binding spare is never used.

fn keep(n: UInt32) : UInt32
  spare = n + 1
  n
end

test "an unused local prevents compilation"
  assert keep(2) == 2
  assert keep(0) == 0
  assert keep(3) == 3
end
