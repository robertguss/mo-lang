module Basics.For
expose first_negative, count_to

intent "for over a range or list with break; not a combinator because of break."

fn first_negative(xs: List(Int32)) : Option(Int32)
  var found = None
  for x in xs
    if x < 0
      found = Some(x)
      break
    end
  end
  found
end

fn count_to(n: UInt32) : UInt32
  var last = 0
  for i in 0..n
    last = i
    break
  end
  last
end

test "break leaves the first match"
  assert first_negative([1, -2, -3]) is Some(n)
  assert n == -2
  assert count_to(3) == 0
end
