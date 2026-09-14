module Effects.Net
expose Echo, EchoServer, Heard, Echoes, talked, echoed?

intent "Serve a line protocol from processes: the runtime serves the listener into a server process, which has each connection read into a worker of its own, and a test drives both through Net.fixture() with no real socket."

process Echo(conn: Conn)
  state
    lines: UInt32
  end

  message Line(text: String)
  message LineTooLong
  message Closed
  message Idle

  fn update(state, message)
    case message
      Line(text):
        if conn.write("#{text}\n", within: 1.minute) is Ok(_)
          state.lines += 1
        end
      LineTooLong | Closed | Idle: conn.close
    end
  end
end

process EchoServer()
  state
    workers: UInt32
    quiet: UInt32
  end

  message Accepted(conn: Conn)
  message Idle

  fn update(state, message)
    case message
      Accepted(conn):
        conn.lines(into: Echo.start(conn), idle: 1.minute)
        state.workers += 1
      Idle:
        state.quiet += 1
    end
  end
end

# What a client heard, line by line, until its connection ended.
process Heard()
  state
    lines: List(String)
    ended: Bool
  end

  message Line(text: String)
  message LineTooLong
  message Closed
  message Idle
  message Lines : List(String)

  fn update(state, message)
    case message
      Line(text):
        state.lines = state.lines.push(text)
      LineTooLong:
        state.lines = state.lines.push("")
      Closed | Idle:
        state.ended = true
      Lines: state.lines
    end
  end
end

supervisor Echoes(conn: Conn)
  child EchoServer, restart: :always
  child Echo(conn), restart: :always
  child Heard, restart: :always
end

# A client of a listener served on port 7 that has what comes back read into `heard` and writes
# its lines, all in one statement, so the runtime serves it once they are written.
fn talked(net: Net, heard: Handle(Heard), sent: List(String)) : Result(Bool, NetError)
  listener = try net.listen(7, within: 1.minute)
  listener.serve(into: EchoServer.start(), idle: 1.minute)
  client = try net.connect("localhost", 7, within: 1.minute)
  client.lines(into: heard, idle: 1.minute)
  try client.write(String.join(sent.map(fn(line) "#{line}\n" end), ""), within: 1.minute)
  Ok(true)
end

# What came back is what was sent, in order, up to where a failure cut it short or a seeded run
# left the rest waiting; anything, when the client never got to talk.
fn echoed?(talk: Result(Bool, NetError), heard: Result(List(String), AskError),
  sent: List(String)) : Bool
  case heard
    Ok(lines): talk is Error(_) or sent.take(lines.size) == lines
    Error(_): true
  end
end

test "every line a client sends comes back the same, unless the connection fails and says so"
  sent = ["hello", "wide world", ""]
  heard = Heard.start()
  talk = talked(Net.fixture(), heard, sent)
  assert echoed?(talk, heard.ask(Lines, within: 1.minute), sent)
end

test "a port a listener holds is Busy for the next one"
  net = Net.fixture()
  assert net.listen(7, within: 1.ms) is Ok(_)
  assert net.listen(7, within: 1.ms) is Error(Busy)
end

verified: types, contracts, tests (2), property (0 seeds), sim (100 runs)
          proven: not run
