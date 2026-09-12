module Basics.Lists
expose score
intent "Transform a list with push, filter, map, and reduce."

fn score(xs: List(UInt32)) : UInt32
  extended = xs.push(4)
  even = extended.filter(fn(x) x % 2 == 0 end)
  doubled = even.map(fn(x) x * 2 end)
  doubled.reduce(0, fn(total, x) total + x end)
end

test "list operations leave the input unchanged"
  xs = [1, 2, 3]
  assert score(xs) == 12
  assert xs.size == 3
  assert xs == [1, 2, 3]
end
