module Processes.Pipeline
expose Sink, Source, Line

intent "Wire two processes together: the source sends each item on to the sink."

process Sink()
  state
    taken: UInt32
  end

  message Take
  message Taken : UInt32

  fn update(state, message)
    case message
      Take:
        state.taken += 1
      Taken: state.taken
    end
  end
end

process Source(sink: Handle(Sink))
  state
    sent: UInt32
  end

  message Produce : UInt32

  fn update(state, message)
    case message
      Produce:
        sink.send(Take)
        state.sent += 1
        state.sent
    end
  end
end

supervisor Line(sink: Handle(Sink))
  child Sink, restart: :always
  child Source(sink), restart: :always
end

test "what the source sends, the sink receives"
  sink = Sink.start()
  source = Source.start(sink)
  assert source.ask(Produce, within: 100.ms) is Ok(1)
  assert sink.ask(Taken, within: 100.ms) is Ok(1)
end
