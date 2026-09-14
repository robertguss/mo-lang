module Rejects.OldParameter
expose grown

intent "old is a keyword: in a contract it names a value before the call, so a parameter cannot take it, even where a struct's field may."

# expect MO0101: expected a name: old is a keyword, the contract's old value, as old(x) in an ensures or an invariant, so a binding or a parameter takes another name, such as before; a struct's field may be named old, and is read after a dot
fn grown(old: UInt32, by: UInt32) : UInt32
  ensures result >= old
  old + by
end

test "grows by what it is given"
  assert grown(1, 2) == 3
end
