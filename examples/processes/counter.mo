module Processes.Counter
expose Counter, Counters, increment
intent "Keep counter state inside a supervised two-message process."

fn increment(n: UInt32) : UInt32
  n + 1
end

process Counter() mailbox: 8
  state
    count: UInt32
  end
  message Increment
  message Reset
  fn update(state, message)
    case message
      Increment:
        state.count = increment(state.count)
      Reset:
        state.count = 0
    end
  end
end

supervisor Counters
  child Counter, restart: :on_crash
end

test "the increment used by update advances the count"
  assert increment(0) == 1
  assert increment(4) == 5
end
