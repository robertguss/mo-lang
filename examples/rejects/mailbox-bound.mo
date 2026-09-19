module Rejects.MailboxBound
expose Counter

intent "A mailbox bound is 1 to 4,294,967,295: one past it is refused when the program is checked, not a panic when it is lowered (step 43)."

# expect MO0217: mailbox: 4294967296 does not fit in a mailbox bound, 1 to 4,294,967,295
process Counter() mailbox: 4294967296
  state
    count: UInt64
  end

  message Count : UInt64

  fn update(state, message)
    case message
      Count: state.count
    end
  end
end

supervisor Counters
  child Counter, restart: :always, max_restarts: 5 per 1.minute
end
