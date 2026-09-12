module Basics.Predicates
expose even?, positive_even?
intent "A predicate dot call passes its receiver as the first argument."

fn even?(n: UInt32) : Bool
  n % 2 == 0
end

fn positive_even?(n: UInt32) : Bool
  n > 0 and n.even?
end

test "direct and dotted predicates agree"
  n = 4
  assert even?(n) == n.even?
  assert n.positive_even?
  assert !positive_even?(0)
end
