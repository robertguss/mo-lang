module Processes.Mailbox
expose Box, Boxes

intent "mailbox: N is a bound; overflow crashes the sender, not the receiver."

process Box() mailbox: 2
  state
    n: UInt32
  end

  message Tick

  fn update(state, message)
    case message
      Tick:
        state.n += 1
    end
  end
end

supervisor Boxes
  child Box, restart: :always
end

test "a bound mailbox still starts"
  h = Box.start()
  h.send(Tick)
  assert h == h
end
