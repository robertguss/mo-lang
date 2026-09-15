# run:
module Programs.NeverRestart
expose Crasher, Crashers, main

intent "A process whose supervisor line says restart: :never stays down after it crashes, under mo run and as a binary: the ask that crashed it and every ask after it are Down, a send to it is dropped, and its crash report on stderr says it was not restarted."

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

fn main(platform: Platform)
  crasher = Crasher.start()
  first = crasher.ask(Bump, within: 1_000.ms)
  after = crasher.ask(Count, within: 1_000.ms)
  crasher.send(Bump)
  again = crasher.ask(Count, within: 1_000.ms)
  platform.stdout.write_line("bump: #{first}, count after: #{after}, after a send: #{again}")
end

verified: types, contracts, tests (0), property (0 seeds), sim (not run)
          proven: not run
