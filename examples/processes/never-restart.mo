module Processes.NeverRestart
expose Crasher, Crashers

intent "A process whose supervisor line says restart: :never stays down after it crashes: an ask to it afterwards is Down within its deadline, and a send to it is dropped with an event."

process Crasher()
  state
    count: UInt64
  end

  invariant "count stays below two"
    state.count < 2
  end

  message Bump : UInt64
  message Count : UInt64

  fn update(state, message)
    case message
      Bump:
        state.count += 2
        state.count
      Count: state.count
    end
  end
end

supervisor Crashers
  child Crasher, restart: :never
end

# Every Bump trips the invariant of a Crasher that answers it. Restarted, the crasher would take all
# five and crash five times, and the runner would give up on it after three, failing the test; kept
# down, it takes the first, and the other four are Down without reaching it.
test rejects "a bump trips the invariant, and every bump after it finds the crasher down"
  crasher = Crasher.start()
  var downs = 0
  for _ in 0..5
    if crasher.ask(Bump, within: 1.minute) is Error(Down)
      downs += 1
    end
  end
  crasher.send(Bump)
  assert downs == 5
end

verified: types, contracts, tests (1), property (0 seeds), sim (100 runs, invariants (kept 1, tripped 1))
          proven: not run
