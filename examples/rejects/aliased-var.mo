module Rejects.AliasedVar
expose shifted
intent "An anonymous argument cannot capture a mutable local."
# expect error: Capturing offset would alias a var from the enclosing scope.

fn shifted(xs: List(UInt32)) : List(UInt32)
  var offset = 1
  offset += 1
  xs.map(fn(x) x + offset end)
end

test "the captured var prevents compilation"
  assert shifted([1, 2]) == [3, 4]
  assert shifted([]) == []
end
