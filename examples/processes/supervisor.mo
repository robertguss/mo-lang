module Processes.Supervisor
expose Heartbeat, Health

intent "Declare how a crashed process restarts, and how many restarts in a window are too many."

process Heartbeat()
  state
    beats: UInt32
  end

  message Beat
  message Beats : UInt32

  fn update(state, message)
    case message
      Beat:
        state.beats += 1
      Beats: state.beats
    end
  end
end

supervisor Health
  child Heartbeat, restart: :always, max_restarts: 5 per 1.minute
end

test "a supervised process takes messages and replies"
  heartbeat = Heartbeat.start()
  heartbeat.send(Beat)
  assert heartbeat.ask(Beats, within: 100.ms) is Ok(1)
end

verified: types, contracts, tests (1), property (0 seeds), sim (100 runs)
          proven: not run
