module Rejects.CatchAllArm
expose Color, code

intent "No catch-all arm on a closed enum."
# expect error: _ as a whole arm on a closed enum is a compile error

enum Color
  Red
  Blue
end

fn code(c: Color) : UInt32
  case c
    Red: 1
    _: 0
  end
end

test "never reached"
  assert code(Red) == 1
end
