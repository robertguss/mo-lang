module Rejects.StateBinding
expose Counter, Counters

intent "state is a keyword inside a process: in an update, state = 1 assigns the process's state, which a number is not, so a binding there takes another name."

# expect MO0206: expected the state of Counter, found an integer
process Counter()
  state
    count: UInt32
  end

  message Bump

  fn update(state, message)
    case message
      Bump:
        state = 1
    end
  end
end

supervisor Counters
  child Counter, restart: :always
end
