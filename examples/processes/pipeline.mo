module Processes.Pipeline
expose Source, Sink, Pipe
intent "Two processes: Source sends to Sink."

process Sink() mailbox: 8
  state
    n: UInt32
  end
  message Ping
  fn update(state, message)
    case message
      Ping:
        state.n += 1
    end
  end
end
process Source(sink: Handle(Sink)) mailbox: 8
  state
    sent: UInt32
  end
  message Kick
  fn update(state, message)
    case message
      Kick:
        sink.send(Ping)
        state.sent += 1
    end
  end
end
supervisor Pipe
  child Sink, restart: :always
  child Source, restart: :always
end

test "source sends to sink"
  sink = Sink.start()
  src = Source.start(sink)
  src.send(Kick)
  assert src == src
end
