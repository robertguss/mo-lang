module Processes.Invariant
expose Counter, Counters, decreased?
intent "Forbid an update that moves the committed count backwards."

fn decreased?(before: UInt32, after: UInt32) : Bool
  after < before
end

process Counter() mailbox: 4
  state
    count: UInt32
  end
  invariant "count never goes backwards"
    decreased?(old(state.count), state.count)
  end
  message Add(amount: UInt32)
  fn update(state, message)
    case message
      Add(amount: n):
        state.count += n
    end
  end
end

supervisor Counters
  child Counter, restart: :on_crash
end

test "the invariant is true exactly for a backward step"
  assert decreased?(3, 2)
  assert !decreased?(3, 3)
  assert !decreased?(3, 4)
end
