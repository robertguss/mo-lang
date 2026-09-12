module Processes.Supervisor
expose Worker, Workers, reset
intent "Declare a restart policy and a maximum of five restarts per minute."

fn reset() : UInt32
  0
end

process Worker() mailbox: 8
  state
    count: UInt32
  end
  message Reset
  fn update(state, message)
    case message
      Reset:
        state.count = reset()
    end
  end
end

supervisor Workers
  child Worker, restart: :always, max_restarts: 5 per 1.minute
end

test "the reset operation used by the supervised worker is deterministic"
  assert reset() == 0
  assert reset() == reset()
end
