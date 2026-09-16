module Processes.CrashKept
expose Counter, Counters, told, main

intent "A crash report is kept apart from the event ring: a process crashes, more updates than the ring holds follow it, and the runtime surface still lists the crash with its clause, the message it crashed on, and its state."

process Counter()
  state
    count: UInt64
  end

  invariant "count stays below a million"
    state.count < 1_000_000
  end

  message Add(n: UInt64)
  message Count : UInt64

  fn update(state, message)
    case message
      Add(n):
        state.count += n
      Count: state.count
    end
  end
end

supervisor Counters
  child Counter, restart: :always
end

# A kept crash as one line, and whether it is a crash at all.
fn told(event: Event) : String
  if event is Crashed(at: _, pid: _, name: name, seed: _, clause: clause, taking: taking,
    snapshot: snapshot)
    "#{name} crashed on #{taking}: #{clause}, state #{snapshot}"
  else
    "not a crash"
  end
end

# The corpus test runs this under mo run --events 64 and as a binary built with --surface and
# MO_EVENTS=64 (toolchain/src/corpus.zig): the crash is 200 updates back, past what the ring holds.
fn main(platform: Platform)
  out = platform.stdout
  case platform.runtime
    Some(runtime):
      counter = Counter.start()
      counter.send(Add(n: 3))
      counter.send(Add(n: 1_000_000))
      var counted = 0
      for _ in 0..200
        if counter.ask(Count, within: 1.minute) is Ok(n) and n == 0
          counted += 1
        end
      end
      out.write("restarted at 0: #{counted >= 199}\n")
      kept = runtime.crashes(5, within: 1.minute)
      out.write("#{kept.size} crash kept\n")
      for event in kept
        out.write("#{told(event)}\n")
      end
      var in_ring = 0
      for event in runtime.recent(0, 64, within: 1.minute)
        if event is Crashed(at: _, pid: _, name: _, seed: _, clause: _, taking: _, snapshot: _)
          in_ring += 1
        end
      end
      out.write("#{in_ring} crashes in the ring's last 64 events\n")
    None: out.write("no runtime: build with --surface\n")
  end
end

test "a crash kept is told with its process, message, clause, and state"
  event = Crashed(at: Time.fixture(), pid: 0, name: "Counter", seed: 0,
    clause: "count stays below a million", taking: "Add(1000000)", snapshot: "Counter(count: 3)")
  assert told(event) == "Counter crashed on Add(1000000): count stays below a million, state Counter(count: 3)"
  assert told(Ended(at: Time.fixture(), pid: 0, name: "Counter")) == "not a crash"
end

verified: types, contracts, tests (1), property (0 seeds), sim (not run)
          proven: not run
