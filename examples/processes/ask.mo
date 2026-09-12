module Processes.Ask
expose Counter, Counters, AskError, read
intent "Ask for a typed reply with a deadline and consume its Result."

enum AskError
  Timeout
end

process Counter() mailbox: 4
  state
    count: UInt32
  end
  message Read : UInt32
  fn update(state, message)
    case message
      Read: state.count
    end
  end
end

supervisor Counters
  child Counter, restart: :on_crash
end

fn read(counter: Handle(Counter)) : Result(UInt32, AskError)
  counter.ask(Read, within: 200.ms)
end

fn value(reply: Result(UInt32, AskError)) : UInt32
  case reply
    Ok(n): n
    Error(Timeout): 0
  end
end

test "the reply consumer handles success and timeout"
  assert value(Ok(3)) == 3
  assert value(Error(Timeout)) == 0
end
