module Processes.Deadline
expose Keeper, Keepers, Literal, Literals, outcome

intent "An ask's deadline reaches the process that answers it: two Fs calls on reply_by share what the asker gave, so the answer comes in time with the second call cut short, where the same two calls on literals each fit and the ask runs out while they finish."

# Reads two files on what remains of the asker's deadline; the second may not take longer than a
# minute, but nothing lets it take longer than the ask.
process Keeper(fs: Fs)
  state
    last: String
  end

  message Both : String
  message Last : String

  fn update(state, message)
    case message
      Both:
        first = fs.read("a.txt", within: reply_by)
        second = fs.read("b.txt", within: reply_by.at_most(1.minute))
        state.last = "#{outcome(first)} #{outcome(second)}"
        state.last
      Last: state.last
    end
  end
end

supervisor Keepers(fs: Fs)
  child Keeper(fs), restart: :always
end

# The same two reads, each on a literal that fits the ask on its own.
process Literal(fs: Fs)
  state
    last: String
  end

  message Both : String
  message Last : String

  fn update(state, message)
    case message
      Both:
        first = fs.read("a.txt", within: 40.ms)
        second = fs.read("b.txt", within: 40.ms)
        state.last = "#{outcome(first)} #{outcome(second)}"
        state.last
      Last: state.last
    end
  end
end

supervisor Literals(fs: Fs)
  child Literal(fs), restart: :always
end

fn outcome(read: Result(String, FsError)) : String
  case read
    Ok(_): "read"
    Error(Timeout): "timeout"
    Error(Missing(_)): "missing"
    Error(NotText): "not text"
  end
end

# Under --sim a fault may fail a read at once, slow it, or hand the keeper its ask with nothing
# left, so each test asserts what holds in every run. In the fixed order the keeper on reply_by
# answers "read timeout" within its 50 ms, and the one on literals reads both files and its ask
# times out.
test "two reads on reply_by share the ask's 50 ms: the keeper always answers in time, never with both"
  fs = Fs.fixture(delay: 30.ms)
  made = fs.write("a.txt", "a", within: 1.minute) is Ok(_) and fs.write("b.txt", "b",
    within: 1.minute) is Ok(_)
  keeper = Keeper.start(fs)
  answered = keeper.ask(Both, within: 50.ms)
  assert answered is Ok(_)
  assert !made or answered != Ok("read read")
end

test "the same reads on literals each fit, and when both finish the ask has run out"
  fs = Fs.fixture(delay: 30.ms)
  made = fs.write("a.txt", "a", within: 1.minute) is Ok(_) and fs.write("b.txt", "b",
    within: 1.minute) is Ok(_)
  literal = Literal.start(fs)
  answered = literal.ask(Both, within: 50.ms)
  if made and literal.ask(Last, within: 1.minute) is Ok(last)
    assert last != "read read" or answered is Error(Timeout)
  end
end

verified: types, contracts, tests (2), property (0 seeds), sim (100 runs)
          proven: not run
