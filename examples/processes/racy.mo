module Processes.Racy
expose Log, Writer, Logs

intent "A race the fixed order hides: the log keeps whichever message reaches it first, which is not always the writer's that was told first, and mo test --sim finds the seeds where it is not."

process Log()
  state
    first: String
  end

  message Add(name: String)
  message First : String

  fn update(state, message)
    case message
      Add(name):
        if state.first == ""
          state.first = name
        end
      First: state.first
    end
  end
end

process Writer(log: Handle(Log))
  state
    sent: UInt32
  end

  message Go(name: String)

  fn update(state, message)
    case message
      Go(name):
        log.send(Add(name: name))
        state.sent += 1
    end
  end
end

supervisor Logs(log: Handle(Log))
  child Log, restart: :always
  child Writer(log), restart: :always
end

test "the writer told first is logged first"
  log = Log.start()
  a = Writer.start(log)
  b = Writer.start(log)
  a.send(Go(name: "a"))
  b.send(Go(name: "b"))
  assert log.ask(First, within: 100.ms) is Ok("a")
end
