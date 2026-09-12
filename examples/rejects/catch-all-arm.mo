module Rejects.CatchAllArm
expose Light, go?

intent "A case on a closed enum names every variant; a catch-all _ arm does not compile."
# expect error: the _ arm hides Red and Yellow; name each variant of Light.

enum Light
  Red
  Yellow
  Green
end

fn go?(light: Light) : Bool
  case light
    Green: true
    _: false
  end
end

test "only green means go"
  assert Green.go?
  assert !Red.go?
end
