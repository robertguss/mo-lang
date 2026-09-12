module Processes.Counter
expose Counter, Counters

intent "A process is state, two messages, and update."

process Counter() mailbox: 32
  state
    n: UInt32
  end

  message Inc
  message Reset

  fn update(state, message)
    case message
      Inc:
        state.n += 1
      Reset:
        state.n = 0
    end
  end
end

supervisor Counters
  child Counter, restart: :always
end

test "start, send, and the box is still a Counter"
  h = Counter.start()
  h.send(Inc)
  assert h == h
end
