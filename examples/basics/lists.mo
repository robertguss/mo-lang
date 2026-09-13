module Basics.Lists
expose add_item, doubled, evens, sum

intent "Build a list, then transform it with map, filter, and reduce instead of a loop."

fn add_item(xs: List(Int32), x: Int32) : List(Int32)
  xs.push(x)
end

fn doubled(xs: List(Int32)) : List(Int32)
  xs.map(fn(x) x * 2 end)
end

fn evens(xs: List(Int32)) : List(Int32)
  xs.filter(fn(x) x % 2 == 0 end)
end

fn sum(xs: List(Int32)) : Int32
  xs.reduce(0, fn(total, x) total + x end)
end

test "push returns a new list and leaves the old one alone"
  xs = [1, 2]
  assert add_item(xs, 3) == [1, 2, 3]
  assert xs == [1, 2]
end

test "map, filter, and reduce"
  xs = [1, 2, 3, 4]
  assert doubled(xs) == [2, 4, 6, 8]
  assert evens(xs) == [2, 4]
  assert sum(xs) == 10
end

verified: types, contracts, tests (2), property (0 seeds), sim (not run)
          proven: not run
