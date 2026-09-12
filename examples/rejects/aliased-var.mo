module Rejects.AliasedVar
expose bigger

intent "A var is never aliased; an anonymous function must not capture one."
# expect error: a var cannot be captured by an anonymous function

fn bigger(xs: List(UInt32)) : List(UInt32)
  var n = 1
  xs.filter(fn(x) x > n end)
end

test "never reached"
  assert bigger([0, 2]).size == 1
end
