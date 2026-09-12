module Rejects.StoredAnonymousFunction
expose apply

intent "Anonymous functions are call arguments only, never stored."
# expect error: an anonymous function may not be bound to a name

fn apply(n: UInt32) : UInt32
  f = fn(x) x + 1 end
  f(n)
end

test "never reached"
  assert apply(1) == 1
end
