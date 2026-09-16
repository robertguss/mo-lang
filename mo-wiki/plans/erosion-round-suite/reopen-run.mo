# run:
module Probe.ReopenRun
expose Reopener, Reopeners

intent "Does a restarted process run its state initializers again, with its capabilities, so it can reopen its store at every start? Printed under mo run."

fn reopen(fs: Fs) : String
  case fs.read("a.txt", within: 1.minute)
    Ok(text): text
    Error(_): "none"
  end
end

process Reopener(fs: Fs)
  state
    opened: String = reopen(fs)
    count: UInt64
  end

  invariant "count stays below two"
    state.count < 2
  end

  message Bump
  message Text : String

  fn update(state, message)
    case message
      Bump:
        state.count += 2
      Text: state.opened
    end
  end
end

supervisor Reopeners(fs: Fs)
  child Reopener(fs), restart: :always
end

fn main(platform: Platform)
  out = platform.stdout
  fs = platform.fs
  wrote1 = fs.write("a.txt", "one", within: 1.minute) is Ok(_)
  r = Reopener.start(fs)
  before = case r.ask(Text, within: 1.minute)
    Ok(t): t
    Error(_): "error"
  end
  wrote2 = fs.write("a.txt", "two", within: 1.minute) is Ok(_)
  r.send(Bump)
  after = case r.ask(Text, within: 1.minute)
    Ok(t): t
    Error(Down): "down"
    Error(_): "error"
  end
  out.write("wrote #{wrote1} #{wrote2}; before #{before}, after the crash and restart #{after}\n")
end
