module Types.Trait
expose Sized, Box, area

intent "A trait plus one impl of one function."

trait Sized
  fn area(s: T) : UInt32
end

struct Box
  w: UInt32
  h: UInt32
end

impl Sized for Box
  fn area(s: Box) : UInt32
    s.w * s.h
  end
end

test "impl is a first-argument function"
  b = Box(w: 2, h: 3)
  assert area(b) == 6
  assert b.area == 6
end
