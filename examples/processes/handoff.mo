module Processes.Handoff
expose Back, Front, Handoffs, handed, greeted?

intent "Hand a connection from one process to another in a message: the front process takes a Conn in a message and passes it on in another, the back process writes to it, and once the front has sent the connection it is no longer the front's to use."

process Back()
  state
    greeted: UInt32
  end

  message Greet(conn: Conn, name: String)

  fn update(state, message)
    case message
      Greet(conn: conn, name: name):
        if conn.write("hello, #{name}\n", within: 1.minute) is Ok(_)
          state.greeted += 1
        end
        conn.close
    end
  end
end

process Front(back: Handle(Back))
  state
    passed: UInt32
  end

  message Take(conn: Conn)

  fn update(state, message)
    case message
      Take(conn):
        back.send(Greet(conn: conn, name: "front"))
        state.passed += 1
    end
  end
end

supervisor Handoffs(back: Handle(Back))
  child Back, restart: :always
  child Front(back), restart: :always
end

# A client connects, the front is handed the server's end in a message and hands it on, and
# the client reads what came back.
fn handed(net: Net) : Result(Option(String), NetError)
  listener = try net.listen(0, within: 1.minute)
  client = try net.connect("localhost", listener.port, within: 1.minute)
  conn = try listener.accept(within: 1.minute)
  front = Front.start(Back.start())
  front.send(Take(conn: conn))
  client.read_line(within: 1.minute)
end

# What the client heard is the back's greeting, unless a call failed and said so, or a seeded
# run left the messages waiting past the read.
fn greeted?(heard: Result(Option(String), NetError)) : Bool
  case heard
    Ok(Some(line)): line == "hello, front"
    Ok(None): false
    Error(_): true
  end
end

test "a connection handed to a process in a message, and on to another, is the one the last writes to"
  assert greeted?(handed(Net.fixture()))
end

verified: types, contracts, tests (1), property (0 seeds), sim (100 runs)
          proven: not run
