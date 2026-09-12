module Basics.Predicates
expose even?

intent "Predicate names end in ?; dot-call is first-argument sugar."

fn even?(n: UInt32) : Bool
  n % 2 == 0
end

test "bare call and dot-call agree"
  assert even?(2)
  assert 2.even?
  assert !even?(1)
  assert !1.even?
end
