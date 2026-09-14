module Rejects.VarState
expose Counter, Counters

intent "state is a keyword inside a process: there it names the process's state, so a var in its update cannot take it, though a plain function's may."

# expect MO0101: expected a name: state is a keyword inside a process, the process's state in its update and invariants, so a binding or a parameter there takes another name, such as status; outside a process state is a name like any other
process Counter()
  state
    count: UInt32
  end

  message Bump(by: UInt32)

  fn update(state, message)
    case message
      Bump(by):
        var state = by
        state += 1
    end
  end
end

supervisor Counters
  child Counter, restart: :always
end
