module Bench.Crunchers
expose Cruncher, Crunching, main

intent "Eight processes, each started by main, so each goes where the fewest live, compute a sum of their own at once and are asked for it after: work that shares nothing, which runs as fast as one core on one scheduler and should run nearly eight times faster on eight."

process Cruncher()
  state
    sum: UInt64
  end

  message Crunch(rounds: UInt64)
  message Sum : UInt64

  fn update(state, message)
    case message
      Crunch(rounds):
        var sum = 0
        for i in 0..rounds
          sum = (sum + i * i) % 1_000_000_007
        end
        state.sum = sum
      Sum: state.sum
    end
  end
end

supervisor Crunching
  child Cruncher, restart: :always
end

fn main(platform: Platform)
  count = (platform.args.first or "8").to_u64 or 8
  rounds = (platform.args.get(1) or "2000000").to_u64 or 2_000_000
  clock = platform.clock
  began = clock.now
  var crunchers = []
  for _ in 0..count
    crunchers = crunchers.push(Cruncher.start())
  end
  for cruncher in crunchers
    cruncher.send(Crunch(rounds: rounds))
  end
  var total = 0
  for cruncher in crunchers
    if cruncher.ask(Sum, within: 600.seconds) is Ok(n)
      total = (total + n) % 1_000_000_007
    end
  end
  took = (clock.now - began).ms
  platform.stdout.write_line("#{count} crunchers, #{rounds} rounds each, sum #{total}: #{took} ms")
end
