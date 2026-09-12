module Basics.Bindings
expose add_one, bump

intent "x = binds once; var may change in place with +=."

fn add_one(n: UInt32) : UInt32
  x = n
  x + 1
end

fn bump(n: UInt32) : UInt32
  var x = n
  x += 1
  x
end

test "both return n plus one"
  assert add_one(1) == 2
  assert bump(1) == 2
end
