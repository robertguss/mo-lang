# run: hello wide world
# run: --clients 3 ping
module Echo.Main
expose Options, options, main

intent "Echo lines over a real TCP socket on 127.0.0.1: an acceptor process hands each connection to a worker of its own, and each client process sends its lines one round trip at a time and prints what came back; a worker serves at most 10,000 lines on one connection."

struct Options
  clients: UInt64
  lines: List(String)
end

process Worker(conn: Conn)
  state
    lines: UInt64
  end

  message Serve

  fn update(state, message)
    case message
      Serve:
        state.lines += serve(conn)
        conn.close
    end
  end
end

process Acceptor(listener: Listener)
  state
    accepted: UInt64
  end

  message Accept

  fn update(state, message)
    case message
      Accept:
        if listener.accept(within: 5_000.ms) is Ok(conn)
          worker = Worker.start(conn)
          worker.send(Serve)
          state.accepted += 1
        end
    end
  end
end

process Client(net: Net, port: UInt16, out: Out, name: String)
  state
    trips: UInt64
  end

  message Talk(lines: List(String)) : UInt64

  fn update(state, message)
    case message
      Talk(lines):
        case talk(net, port, lines)
          Ok(heard):
            for pair in lines.zip(heard)
              out.write_line("#{name} sent #{pair.0}")
              out.write_line("#{name} heard #{pair.1}")
            end
            state.trips += heard.size
          Error(e): out.write_line("#{name} failed: #{e}")
        end
        state.trips
    end
  end
end

supervisor Echoes(listener: Listener, conn: Conn, net: Net, port: UInt16, out: Out)
  child Acceptor(listener), restart: :always
  child Worker(conn), restart: :always
  child Client(net, port, out, "client"), restart: :always
end

fn options(args: List(String)) : Options
  if args.first == Some("--clients")
    n = (args.get(1) or "1").to_u64 or 1
    return Options(clients: n, lines: args.drop(2))
  end
  Options(clients: 1, lines: args)
end

fn serve(conn: Conn) : UInt64
  var lines = 0
  for _ in 0..10_000
    line = conn.read_line(within: 5_000.ms)
    if line is Ok(Some(text))
      if conn.write("#{text}\n", within: 5_000.ms) is Error(_)
        break
      end
      lines += 1
    else
      break
    end
  end
  lines
end

fn talk(net: Net, port: UInt16, sent: List(String)) : Result(List(String), NetError)
  conn = try net.connect("127.0.0.1", port, within: 5_000.ms)
  var heard = sent.take(0)
  for line in sent
    try conn.write("#{line}\n", within: 5_000.ms)
    echoed = try conn.read_line(within: 5_000.ms)
    heard = heard.push(echoed or "nothing")
  end
  conn.close
  Ok(heard)
end

fn run(net: Net, out: Out, given: Options) : Result(UInt64, NetError)
  listener = try net.listen(0, within: 5_000.ms)
  acceptor = Acceptor.start(listener)
  var trips = 0
  for i in 0..given.clients
    acceptor.send(Accept)
    client = Client.start(net, listener.port, out, "client #{i}")
    if client.ask(Talk(lines: given.lines), within: 5_000.ms) is Ok(n)
      trips += n
    end
  end
  Ok(trips)
end

fn main(platform: Platform)
  given = options(platform.args)
  case run(platform.net, platform.stdout, given)
    Ok(trips):
      platform.stdout.write_line("#{trips} round trips over 127.0.0.1")
      if trips != given.clients * given.lines.size
        platform.exit(1)
      end
    Error(e):
      platform.stderr.write_line("echo failed: #{e}")
      platform.exit(1)
  end
end

test "--clients takes a count, and the rest are the lines"
  assert options(["--clients", "3", "ping"]) == Options(clients: 3, lines: ["ping"])
  assert options(["hello", "world"]) == Options(clients: 1, lines: ["hello", "world"])
end

verified: types, contracts, tests (1), property (0 seeds), sim (not run)
          proven: not run
