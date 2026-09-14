module Hold
expose Worker, Registry, Registries, main

intent "Probe: a registry whose state holds 10,000 workers' handles keeps them alive, and once it forgets them they end."

process Worker(key: UInt64)
  state
    count: UInt64
  end

  message Count : UInt64

  fn update(state, message)
    case message
      Count:
        state.count += 1
        state.count
    end
  end
end

process Registry()
  state
    workers: Map(UInt64, Handle(Worker))
  end

  message Add(from: UInt64, to: UInt64) : UInt64
  message Drop : UInt64
  message Size : UInt64

  fn update(state, message)
    case message
      Add(from: from, to: to):
        for key in from..to
          state.workers = state.workers.set(key, Worker.start(key))
        end
        state.workers.size
      Drop:
        state.workers = Map.new()
        0
      Size: state.workers.size
    end
  end
end

supervisor Registries(key: UInt64)
  child Registry, restart: :always
  child Worker(key), restart: :never
end

fn main(platform: Platform)
  registry = Registry.start()
  added = registry.ask(Add(from: 0, to: 10_000), within: 1.minute)
  var answered = 0
  for _ in 0..25_000
    if registry.ask(Size, within: 1.minute) is Ok(_)
      answered += 1
    end
  end
  case platform.runtime
    Some(runtime):
      live = runtime.processes(within: 1.minute).size
      memory = Json.encode(runtime.memory(within: 1.minute))
      platform.stdout.write("held: added #{added}, asked #{answered}, live #{live}, #{memory}\n")
      dropped = registry.ask(Drop, within: 1.minute)
      for _ in 0..25_000
        if registry.ask(Size, within: 1.minute) is Ok(_)
          answered += 1
        end
      end
      # A start from main past the sweep's count settles first, and the sweep ends what it can.
      late = Worker.start(10_001).ask(Count, within: 1.minute)
      after = runtime.processes(within: 1.minute).size
      platform.stdout.write("dropped: #{dropped}, asked #{answered}, late #{late}, live #{after}\n")
    None:
      platform.stdout.write("no runtime surface\n")
  end
end
