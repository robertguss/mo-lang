module Basics.Tuples
expose pair, first, swap

intent "Build a tuple, read .0, destructure in case."

fn pair(a: UInt32, b: UInt32) : (UInt32, UInt32)
  (a, b)
end

fn first(p: (UInt32, UInt32)) : UInt32
  p.0
end

fn swap(p: (UInt32, UInt32)) : (UInt32, UInt32)
  case p
    (a, b): (b, a)
  end
end

test "build, index, destructure"
  p = pair(1, 2)
  assert first(p) == 1
  assert swap(p) == (2, 1)
end
