module Processes.Counter
expose Counter, Counters

intent "Keep a count inside a process, where it changes one message at a time."

process Counter()
  state
    count: UInt32
  end

  message Increment
  message Reset

  fn update(state, message)
    case message
      Increment:
        state.count += 1
      Reset:
        state.count = 0
    end
  end
end

supervisor Counters
  child Counter, restart: :always
end

test "a counter takes its messages without blocking the sender"
  counter = Counter.start()
  counter.send(Increment)
  counter.send(Reset)
end

verified: types, contracts, tests (1), property (0 seeds), sim (100 runs)
          proven: not run
