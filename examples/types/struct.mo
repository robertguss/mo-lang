module Types.Struct
expose Point, moved

intent "Named construction; change a struct only via a var copy."

struct Point
  x: Int32
  y: Int32
end

fn moved(p: Point, dx: Int32) : Point
  var copy = p
  copy.x = p.x + dx
  copy
end

test "construct and update a copy"
  p = Point(x: 1, y: 2)
  q = moved(p, 3)
  assert q.x == 4
  assert p.x == 1
end
