module Rejects.StateBinding
expose counted

intent "state is a keyword: alone it names a process's state, so a binding cannot take it, even where a struct's field may."

# expect MO0201: there is no state outside a process: state is a keyword, the process's state in its update and invariants, so a binding takes another name, such as status, and a struct's field named state is read after a dot; no state is in scope
fn counted(n: UInt32) : UInt32
  state = 1
  n + state
end

test "one more"
  assert counted(1) == 2
end
