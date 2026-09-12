module Rejects.CatchAllArm
expose Switch, on?
intent "Name every variant of a closed enum instead of using a catch-all."
# expect error: A closed enum case cannot have a whole-arm underscore pattern.

enum Switch
  On
  Off
end

fn on?(switch: Switch) : Bool
  case switch
    On: true
    _: false
  end
end

test "a catch-all prevents compilation even when it covers Off"
  assert on?(On)
  assert !on?(Off)
end
