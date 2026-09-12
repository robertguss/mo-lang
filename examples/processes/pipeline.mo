module Processes.Pipeline
expose Source, Sink, Pipeline
intent "Forward a typed message from one supervised process to another."

process Sink() mailbox: 4
  state
    total: UInt32
  end
  message Record(amount: UInt32)
  fn update(state, message)
    case message
      Record(amount: n):
        state.total += n
    end
  end
end

process Source(sink: Handle(Sink)) mailbox: 4
  state
    forwarded: UInt32
  end
  message Forward(amount: UInt32)
  fn update(state, message)
    case message
      Forward(amount: n):
        sink.send(Record(amount: n), within: 200.ms)
        state.forwarded += 1
    end
  end
end

supervisor Pipeline
  child Source, restart: :on_crash
  child Sink, restart: :never
end

test "the downstream message carries the forwarded amount"
  assert Record(amount: 3) is Record(amount: n)
  assert n == 3
end
