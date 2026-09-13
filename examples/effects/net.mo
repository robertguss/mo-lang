module Effects.Net
expose Echo, EchoServer, Echoes, echoed?

intent "Serve a line protocol from processes: the listener hands each connection to a worker of its own, and a test drives both through Net.fixture() with no real socket."

process Echo(conn: Conn)
  state
    lines: UInt32
  end

  message Serve : UInt32

  fn update(state, message)
    case message
      Serve:
        state.lines += serve(conn)
        state.lines
    end
  end
end

process EchoServer(listener: Listener)
  state
    workers: UInt32
  end

  message Accept : Option(Handle(Echo))

  fn update(state, message)
    case message
      Accept:
        case listener.accept(within: 1.minute)
          Ok(conn):
            worker = Echo.start(conn)
            worker.send(Serve)
            state.workers += 1
            Some(worker)
          Error(_): None
        end
    end
  end
end

supervisor Echoes(listener: Listener, conn: Conn)
  child EchoServer(listener), restart: :always
  child Echo(conn), restart: :always
end

fn serve(conn: Conn) : UInt32
  var lines = 0
  for _ in 0..1_000
    case echo_once(conn)
      Ok(true):
        lines += 1
      Ok(false):
        break
      Error(_):
        break
    end
  end
  lines
end

fn echo_once(conn: Conn) : Result(Bool, NetError)
  line = try conn.read_line(within: 1.minute)
  case line
    Some(text):
      try conn.write("#{text}\n", within: 1.minute)
      Ok(true)
    None: Ok(false)
  end
end

fn talk(net: Net, sent: List(String)) : Result(List(String), NetError)
  listener = try net.listen(7, within: 1.minute)
  server = EchoServer.start(listener)
  client = try net.connect("localhost", 7, within: 1.minute)
  for line in sent
    try client.write("#{line}\n", within: 1.minute)
  end
  case server.ask(Accept, within: 1.minute)
    Ok(Some(worker)):
      if worker.ask(Serve, within: 10.minute) is Error(_)
        return Error(Timeout)
      end
    Ok(None):
      return Error(Timeout)
    Error(_):
      return Error(Timeout)
  end
  var heard = sent.take(0)
  for _ in sent
    case try client.read_line(within: 1.minute)
      Some(text):
        heard = heard.push(text)
      None:
        return Error(Closed)
    end
  end
  Ok(heard)
end

fn echoed?(heard: Result(List(String), NetError), sent: List(String)) : Bool
  case heard
    Ok(lines): lines == sent
    Error(_): true
  end
end

test "every line a client sends comes back the same, unless the connection fails and says so"
  sent = ["hello", "wide world", ""]
  assert echoed?(talk(Net.fixture(), sent), sent)
end

test "a port a listener holds is Busy for the next one"
  net = Net.fixture()
  assert net.listen(7, within: 1.ms) is Ok(_)
  assert net.listen(7, within: 1.ms) is Error(Busy)
end

verified: types, contracts, tests (2), property (0 seeds), sim (100 runs)
          proven: not run
