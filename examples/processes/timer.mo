module Processes.Timer
expose Ticker, Tickers

intent "A process sends itself a Tick on a delay and stops after three: the runtime waits between the ticks, and the process never loops."

process Ticker()
  state
    ticks: UInt64
  end

  message Start(me: Handle(Ticker))
  message Tick(me: Handle(Ticker))
  message Ticks : UInt64

  fn update(state, message)
    case message
      Start(me): me.send(Tick(me: me), delay: 10.ms)
      Tick(me):
        state.ticks += 1
        if state.ticks < 3
          me.send(Tick(me: me), delay: 10.ms)
        end
      Ticks: state.ticks
    end
  end
end

supervisor Tickers
  child Ticker, restart: :always
end

# Simulated time passes only while a call waits, so before each look the test waits in a fixture
# that answers after 10 ms; under a seed a look may come before a tick, so it looks until it has
# seen all three.
test "a ticker sends itself three ticks on a delay, and stops"
  ticker = Ticker.start()
  ticker.send(Start(me: ticker))
  slow = Fs.fixture(delay: 10.ms)
  var seen = 0
  for _ in 0..40
    if slow.list(within: 1.minute) is Ok(_) and ticker.ask(Ticks, within: 1.minute) is Ok(n)
      seen = n
    end
  end
  assert seen == 3
end

verified: types, contracts, tests (1), property (0 seeds), sim (100 runs)
          proven: not run
