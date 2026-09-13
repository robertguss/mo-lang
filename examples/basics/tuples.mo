module Basics.Tuples
expose sorted_pair, low, spread

intent "Group two values without a struct, then read them by position or take them apart."

fn sorted_pair(a: Int32, b: Int32) : (Int32, Int32)
  if a <= b
    (a, b)
  else
    (b, a)
  end
end

fn low(pair: (Int32, Int32)) : Int32
  pair.0
end

fn spread(pair: (Int32, Int32)) : Int32
  case pair
    (first, second): second - first
  end
end

test "a pair is built in order and read two ways"
  pair = sorted_pair(9, 4)
  assert pair == (4, 9)
  assert low(pair) == 4
  assert spread(pair) == 5
end

verified: types, contracts, tests (1), property (0 seeds), sim (not run)
          proven: not run
