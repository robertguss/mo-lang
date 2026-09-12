module Processes.Invariant
expose Counter, Counters

intent "invariant with old(state.n) is checked after every update."

process Counter() mailbox: 32
  state
    n: UInt32
  end

  invariant "n never goes backwards"
    state.n >= old(state.n)
  end

  message Inc

  fn update(state, message)
    case message
      Inc:
        state.n += 1
    end
  end
end

supervisor Counters
  child Counter, restart: :always
end

test "inc is allowed by the invariant"
  h = Counter.start()
  h.send(Inc)
  assert h == h
end
