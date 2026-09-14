module Processes.Registry
expose Worker, Registry, Registries

intent "A registry keeps a worker per key in its state: it starts a worker the first time a key is bumped, routes each bump to that key's worker through its map, and forgets a key when told, after which nothing holds the worker and it ends."

process Worker(key: String)
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

# The registry's state holds the handles, so each worker lives as long as its key is in the map.
process Registry()
  state
    workers: Map(String, Handle(Worker))
  end

  message Bump(key: String) : UInt64
  message Forget(key: String)
  message Keys : UInt64

  fn update(state, message)
    case message
      Bump(key):
        worker = case state.workers.get(key)
          Some(held): held
          None: Worker.start(key)
        end
        state.workers = state.workers.set(key, worker)
        case worker.ask(Count, within: 1.minute)
          Ok(n): n
          Error(_): 0
        end
      Forget(key):
        state.workers = state.workers.remove(key)
      Keys: state.workers.size
    end
  end
end

supervisor Registries(key: String)
  child Registry, restart: :always
  child Worker(key), restart: :never
end

test "a registry routes each key to its own worker"
  registry = Registry.start()
  assert registry.ask(Bump(key: "a"), within: 1.minute) is Ok(1)
  assert registry.ask(Bump(key: "a"), within: 1.minute) is Ok(2)
  assert registry.ask(Bump(key: "b"), within: 1.minute) is Ok(1)
  assert registry.ask(Keys, within: 1.minute) is Ok(2)
end

test "a worker whose key the registry forgets ends, and the one it keeps lives"
  runtime = Runtime.fixture()
  registry = Registry.start()
  assert registry.ask(Bump(key: "a"), within: 1.minute) is Ok(1)
  assert registry.ask(Bump(key: "b"), within: 1.minute) is Ok(1)
  assert runtime.processes(within: 1.minute).size == 3
  registry.send(Forget(key: "a"))
  assert registry.ask(Keys, within: 1.minute) is Ok(1)
  names = runtime.processes(within: 1.minute).map(fn(info) info.name end)
  assert names == ["Registry", "Worker"]
  assert registry.ask(Bump(key: "b"), within: 1.minute) is Ok(2)
end

verified: types, contracts, tests (2), property (0 seeds), sim (100 runs)
          proven: not run
