module Rejects.VarState
expose counted

intent "state is a keyword: alone it names a process's state, so a var cannot take it, even where a struct's field may."

# expect MO0101: expected a name: state is a keyword, the process's state in its update and invariants, so a binding or a parameter takes another name, such as status; a struct's field may be named state, and is read after a dot
fn counted(n: UInt32) : UInt32
  var state = n
  state += 1
  state
end

test "one more"
  assert counted(1) == 2
end
