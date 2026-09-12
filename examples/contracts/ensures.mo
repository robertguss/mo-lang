module Contracts.Ensures
expose BumpError, bump

intent "ensures uses result, old, is, and implies."

enum BumpError
  Overflow
end

fn bump(inout n: UInt32) : Result(UInt32, BumpError)
  ensures result is Ok(v) implies v == old(n) + 1

  n += 1
  Ok(n)
end

test "result is the bumped value"
  var n = 1
  r = bump(n)
  assert r is Ok(v)
  assert v == 2
  assert n == 2
end
