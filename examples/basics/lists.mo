module Basics.Lists
expose grown, scaled, positives, total

intent "List literal, push, map, filter, and reduce."

fn grown(xs: List(UInt32)) : List(UInt32)
  xs.push(4)
end

fn scaled(xs: List(UInt32)) : List(UInt32)
  xs.map(fn(x) x + 1 end)
end

fn positives(xs: List(UInt32)) : List(UInt32)
  xs.filter(fn(x) x > 0 end)
end

fn total(xs: List(UInt32)) : UInt32
  xs.reduce(0, fn(acc, x) acc + x end)
end

test "literal and combinators"
  xs = [1, 2, 3]
  assert grown(xs).size == 4
  assert total(scaled([1])) == 2
  assert positives([0, 1]).size == 1
end
