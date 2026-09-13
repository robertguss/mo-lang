# run: 2000
module Ends.Main
expose Idle, Keeper, Relay, Ends, main

intent "Start a process per iteration and send it one message, as a program that starts a worker per request does, while a keeper reachable only through a relay's start arguments counts every iteration: each idle process that finished is freed, and the keeper and the relay never are."

process Idle()
  state
    pokes: UInt64
  end

  message Poke

  fn update(state, message)
    case message
      Poke:
        state.pokes += 1
    end
  end
end

process Keeper()
  state
    pokes: UInt64
  end

  message Poke
  message Pokes : UInt64

  fn update(state, message)
    case message
      Poke:
        state.pokes += 1
      Pokes: state.pokes
    end
  end
end

process Relay(keeper: Handle(Keeper))
  state
    passed: UInt64
  end

  message Pass
  message Count : UInt64

  fn update(state, message)
    case message
      Pass:
        keeper.send(Poke)
        state.passed += 1
      Count:
        case keeper.ask(Pokes, within: 1.minute)
          Ok(n): n
          Error(_): 0
        end
    end
  end
end

supervisor Ends(keeper: Handle(Keeper))
  child Idle, restart: :always
  child Keeper, restart: :always
  child Relay(keeper), restart: :always
end

fn started(iterations: UInt64, relay: Handle(Relay)) : UInt64
  var count = 0
  for _ in 0..iterations
    idle = Idle.start()
    idle.send(Poke)
    relay.send(Pass)
    count += 1
  end
  count
end

fn main(platform: Platform)
  iterations = (platform.args.first or "1000").to_u64 or 1000
  relay = Relay.start(Keeper.start())
  platform.stdout.write_line("started #{started(iterations, relay)}")
  case relay.ask(Count, within: 1.minute)
    Ok(n): platform.stdout.write_line("the keeper counted #{n}")
    Error(e): platform.stdout.write_line("the keeper is gone: #{e}")
  end
end

verified: types, contracts, tests (0), property (0 seeds), sim (not run)
          proven: not run
