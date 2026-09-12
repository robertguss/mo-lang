module Processes.Supervisor
expose Worker, Workers

intent "A supervisor names restart: and max_restarts:."

process Worker() mailbox: 8
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

supervisor Workers
  child Worker, restart: :always, max_restarts: 5 per 1.minute
end

test "the child starts under the supervisor"
  h = Worker.start()
  h.send(Tick)
  assert h == h
end
