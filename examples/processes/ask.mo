module Processes.Ask
expose Counter, Counters

intent "A message with a reply type; ask carries within:."

process Counter() mailbox: 32
  state
    n: UInt32
  end

  message Inc
  message Get : UInt32

  fn update(state, message)
    case message
      Inc:
        state.n += 1
      Get:
        state.n = state.n
    end
  end
end

supervisor Counters
  child Counter, restart: :always
end

test "ask returns a Result"
  h = Counter.start()
  h.send(Inc)
  r = h.ask(Get, within: 50.ms)
  assert r is Ok(n)
  assert n == n
end
