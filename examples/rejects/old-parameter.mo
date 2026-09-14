module Rejects.OldParameter
expose doubled

intent "old is a keyword inside an ensures: there old(x) is x's value before the call, so an anonymous function's parameter in it cannot take the name, though one in a body may."

# expect MO0101: expected a name: old is a keyword inside an ensures or an invariant, where old(x) is x's value before the call or the update, so a binding there takes another name, such as before; elsewhere old is a name like any other
fn doubled(xs: List(UInt32)) : List(UInt32)
  ensures result.map(fn(old) old / 2 end) == xs

  xs.map(fn(x) x * 2 end)
end

test "each number doubles"
  assert doubled([1, 2]) == [2, 4]
end
