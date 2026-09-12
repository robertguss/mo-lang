module Rejects.UnsupervisedProcess
expose Counter

intent "Every process runs under a supervisor; a process that no supervisor names does not compile."
# expect error: Counter is not a child of any supervisor; add a supervisor with child Counter.

process Counter()
  state
    count: UInt32
  end

  message Increment
  message Count : UInt32

  fn update(state, message)
    case message
      Increment:
        state.count += 1
      Count: state.count
    end
  end
end

test "a counter counts"
  counter = Counter.start()
  counter.send(Increment)
  assert counter.ask(Count, within: 100.ms) is Ok(1)
end
