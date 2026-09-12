module Rejects.StoredAnonymousFunction
expose advance
intent "Anonymous functions belong directly in call arguments."
# expect error: An anonymous function cannot be stored in a binding.

fn advance(n: UInt32) : UInt32
  step = fn(x) x + 1 end
  step(n)
end

test "calling the stored function does not make the binding legal"
  assert advance(0) == 1
  assert advance(1) == 2
  assert advance(2) == 3
end
