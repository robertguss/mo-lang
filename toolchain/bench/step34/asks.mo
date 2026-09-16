module Bench.Asks
expose Ponger, Pinger, Asking, main

intent "100,000 asks from one process to another, both on one scheduler (the pinger starts the ponger, so it lands on the pinger's) or on two (main starts both, so each goes where the fewest live): the cost of an ask that crosses schedulers against one that does not."

process Ponger()
  state
    pongs: UInt64
  end

  message Ping : UInt64

  fn update(state, message)
    case message
      Ping:
        state.pongs += 1
        state.pongs
    end
  end
end

process Pinger(given: Option(Handle(Ponger)))
  state
    pongs: UInt64
  end

  message Go(count: UInt64) : UInt64

  fn update(state, message)
    case message
      Go(count):
        target = given or Ponger.start()
        var got = 0
        for _ in 0..count
          if target.ask(Ping, within: 1.minute) is Ok(n)
            got = n
          end
        end
        state.pongs = got
        state.pongs
    end
  end
end

supervisor Asking(given: Option(Handle(Ponger)))
  child Ponger, restart: :always
  child Pinger(given), restart: :always
end

fn main(platform: Platform)
  count = (platform.args.first or "100000").to_u64 or 100_000
  apart = platform.args.get(1) == Some("apart")
  clock = platform.clock
  given = if apart
    Some(Ponger.start())
  else
    None
  end
  pinger = Pinger.start(given)
  began = clock.now
  answered = case pinger.ask(Go(count: count), within: 600.seconds)
    Ok(n): n
    Error(_): 0
  end
  took = (clock.now - began).ms
  placing = if apart
    "two schedulers"
  else
    "one scheduler"
  end
  platform.stdout.write_line("#{answered} asks, #{placing}: #{took} ms")
end
