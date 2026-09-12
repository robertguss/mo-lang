module Processes.Mailbox
expose Inbox, Inboxes, full?
intent "A full mailbox crashes the sender; this inbox holds two messages."

fn full?(queued: UInt32) : Bool
  queued >= 2
end

process Inbox() mailbox: 2
  state
    count: UInt32
  end
  message Tick
  fn update(state, message)
    case message
      Tick:
        state.count += 1
    end
  end
end

supervisor Inboxes
  child Inbox, restart: :on_crash
end

test "the declared mailbox boundary is two"
  assert !full?(1)
  assert full?(2)
end
