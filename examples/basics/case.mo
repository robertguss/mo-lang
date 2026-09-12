module Basics.Case
expose classify

intent "Guards, nested destructuring, literal arms, and _ inside a pattern."

enum Box
  Pair(left: UInt32, right: UInt32)
  Tag(n: UInt32)
end

fn classify(b: Box) : UInt32
  case b
    Pair(left: 0, right: r): r
    Pair(left: l, right: _) if l > 9:
      l
    Pair(left: l, right: r):
      l + r
    Tag(n: 1): 1
    Tag(n: n): n
  end
end

test "guard, nested fields, literal, wildcard"
  assert classify(Pair(left: 0, right: 4)) == 4
  assert classify(Pair(left: 10, right: 1)) == 10
  assert classify(Tag(n: 1)) == 1
end
