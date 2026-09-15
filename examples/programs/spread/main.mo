# run: 2000
module Spread.Main
expose Idle, Tally, Spawner, Launcher, Spread, main

intent "Start short-lived processes from several spawners at once, which a program on more cores than one places on several schedulers: each spawner asks every idle process it starts once, which is then freed, and tells a tally how many answered; the count is the same whatever scheduler each process ran on."

process Idle()
  state
    poked: Bool
  end

  message Poke : Bool

  fn update(state, message)
    case message
      Poke:
        state.poked = true
        state.poked
    end
  end
end

process Tally() mailbox: 4_096
  state
    counted: UInt64
  end

  message Counted(n: UInt64)
  message Total : UInt64

  fn update(state, message)
    case message
      Counted(n):
        state.counted += n
      Total: state.counted
    end
  end
end

process Spawner(tally: Handle(Tally)) mailbox: 4_096
  state
    answered: UInt64
  end

  message Spawn(count: UInt64)
  message Answered : UInt64

  fn update(state, message)
    case message
      Spawn(count):
        var answered = 0
        for _ in 0..count
          if Idle.start().ask(Poke, within: 1.minute) is Ok(true)
            answered += 1
          end
        end
        counted = answered
        state.answered += counted
        tally.send(Counted(n: counted))
      Answered: state.answered
    end
  end
end

process Launcher()
  state
    launched: UInt64
  end

  message Launch(spawners: List(Handle(Spawner)), batches: UInt64, each: UInt64)

  fn update(state, message)
    case message
      Launch(spawners: spawners, batches: batches, each: each):
        # A batch a message, so a spawner's processes are freed between its updates on one core too.
        for _ in 0..batches
          for spawner in spawners
            spawner.send(Spawn(count: each))
          end
        end
        state.launched += 1
    end
  end
end

supervisor Spread(tally: Handle(Tally))
  child Idle, restart: :never
  child Tally, restart: :always
  child Spawner(tally), restart: :always
  child Launcher, restart: :always
end

fn answered(spawners: List(Handle(Spawner))) : UInt64
  spawners.reduce(0, fn(sum, spawner) sum + asked(spawner.ask(Answered, within: 1.minute)) end)
end

fn asked(got: Result(UInt64, AskError)) : UInt64
  case got
    Ok(n): n
    Error(_): 0
  end
end

fn main(platform: Platform)
  total = (platform.args.first or "2000").to_u64 or 2_000
  tally = Tally.start()
  spawners = [Spawner.start(tally),
    Spawner.start(tally),
    Spawner.start(tally),
    Spawner.start(tally)]
  Launcher.start().send(Launch(spawners: spawners, batches: total / 400, each: 100))
  platform.stdout.write_line("#{answered(spawners)} idle processes answered, started by #{spawners.size} spawners")
  case tally.ask(Total, within: 1.minute)
    Ok(n): platform.stdout.write_line("the tally counted #{n}")
    Error(e): platform.stdout.write_line("the tally is gone: #{e}")
  end
end

verified: types, contracts, tests (0), property (0 seeds), sim (not run)
          proven: not run
