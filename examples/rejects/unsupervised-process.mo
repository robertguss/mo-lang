module Rejects.UnsupervisedProcess
expose Lone

intent "A process not under a supervisor does not compile."
# expect error: a process must be a child of a supervisor

process Lone() mailbox: 8
  state
    n: UInt32
  end

  message Tick

  fn update(state, message)
    case message
      Tick:
        state.n += 1
    end
  end
end

test "never reached"
  h = Lone.start()
  assert h == h
end
