module Types.Enum
expose Shape, area

intent "Enum data variants and exhaustive matching."

enum Shape
  Circle(radius: UInt32)
  Rect(w: UInt32, h: UInt32)
end

fn area(s: Shape) : UInt32
  case s
    Circle(radius: r): r * r
    Rect(w: w, h: h): w * h
  end
end

test "each variant carries data"
  assert area(Circle(radius: 2)) == 4
  assert area(Rect(w: 2, h: 3)) == 6
end
