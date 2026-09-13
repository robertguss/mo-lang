module Basics.Case
expose Shape, describe

intent "Match a value against patterns top to bottom, and cover every shape it can take."

enum Shape
  Circle(radius: UInt32)
  Rect(size: (UInt32, UInt32))
end

fn describe(shape: Shape) : String
  case shape
    Circle(0): "a dot"
    Circle(r) if r > 100: "a big circle"
    Circle(_): "a circle"
    Rect((w, h)) if w == h: "a square of side #{w}"
    Rect((_, 0)): "a flat line"
    Rect((w, h)): "a #{w} by #{h} rectangle"
  end
end

test "literal arms and guards"
  assert Circle(radius: 0).describe == "a dot"
  assert Circle(radius: 500).describe == "a big circle"
  assert Circle(radius: 5).describe == "a circle"
end

test "a tuple destructured inside a variant"
  assert Rect(size: (3, 3)).describe == "a square of side 3"
  assert Rect(size: (4, 0)).describe == "a flat line"
  assert Rect(size: (4, 2)).describe == "a 4 by 2 rectangle"
end
