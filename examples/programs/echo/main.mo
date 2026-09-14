# run: hello wide world
# run: --clients 3 ping
module Echo.Main
expose Options, options, code_of, main

intent "Echo lines over a real TCP socket on 127.0.0.1: the runtime serves the listener into an acceptor process, which reads each connection into a worker of its own, and each client process sends its lines one round trip at a time and prints what came back."

struct Options
  clients: UInt64
  lines: List(String)
end

process Worker(conn: Conn)
  state
    lines: UInt64
  end

  message Line(text: String)
  message LineTooLong
  message Closed
  message Idle

  fn update(state, message)
    case message
      Line(text):
        if conn.write("#{text}\n", within: 5_000.ms) is Ok(_)
          state.lines += 1
        else
          conn.close
        end
      LineTooLong | Closed | Idle: conn.close
    end
  end
end

process Acceptor()
  state
    accepted: UInt64
    quiet: UInt64
  end

  message Accepted(conn: Conn)
  message Idle

  fn update(state, message)
    case message
      Accepted(conn):
        conn.lines(into: Worker.start(conn), idle: 5_000.ms)
        state.accepted += 1
      Idle:
        state.quiet += 1
    end
  end
end

# One round trip per message: the line out, and the line that came back.
process Client(conn: Conn, out: Out, name: String)
  state
    trips: UInt64
  end

  message Say(line: String) : UInt64

  fn update(state, message)
    case message
      Say(line):
        case said(conn, line)
          Ok(heard):
            out.write_line("#{name} sent #{line}")
            out.write_line("#{name} heard #{heard}")
            state.trips += 1
          Error(e): out.write_line("#{name} failed: #{e}")
        end
        state.trips
    end
  end
end

supervisor Echoes(conn: Conn, out: Out)
  child Acceptor, restart: :always
  child Worker(conn), restart: :always
  child Client(conn, out, "client"), restart: :always
end

fn options(args: List(String)) : Options
  if args.first == Some("--clients")
    n = (args.get(1) or "1").to_u64 or 1
    return Options(clients: n, lines: args.drop(2))
  end
  Options(clients: 1, lines: args)
end

fn said(conn: Conn, line: String) : Result(String, NetError)
  try conn.write("#{line}\n", within: 5_000.ms)
  echoed = try conn.read_line(within: 5_000.ms)
  Ok(echoed or "nothing")
end

# A client of its own on a connection of its own, one ask per line; the trips it made.
fn talked(net: Net, port: UInt16, out: Out, name: String, lines: List(String)) : Result(UInt64,
  NetError)
  conn = try net.connect("127.0.0.1", port, within: 5_000.ms)
  client = Client.start(conn, out, name)
  var trips = 0
  for line in lines
    if client.ask(Say(line: line), within: 5_000.ms) is Ok(n)
      trips = n
    end
  end
  conn.close
  Ok(trips)
end

fn run(net: Net, out: Out, given: Options) : Result(UInt64, NetError)
  listener = try net.listen(0, within: 5_000.ms)
  listener.serve(into: Acceptor.start(), idle: 5_000.ms)
  var trips = 0
  for i in 0..given.clients
    case talked(net, listener.port, out, "client #{i}", given.lines)
      Ok(n):
        trips += n
      Error(e): out.write_line("client #{i} failed: #{e}")
    end
  end
  Ok(trips)
end

# 0 when every line came back, else 1.
fn code_of(trips: UInt64, given: Options) : UInt8
  if trips == given.clients * given.lines.size
    return 0
  end
  1
end

# The listener is served until the program ends, so main ends it with exit.
fn main(platform: Platform)
  given = options(platform.args)
  case run(platform.net, platform.stdout, given)
    Ok(trips):
      platform.stdout.write_line("#{trips} round trips over 127.0.0.1")
      platform.exit(code_of(trips, given))
    Error(e):
      platform.stderr.write_line("echo failed: #{e}")
      platform.exit(1)
  end
end

test "--clients takes a count, and the rest are the lines"
  assert options(["--clients", "3", "ping"]) == Options(clients: 3, lines: ["ping"])
  assert options(["hello", "world"]) == Options(clients: 1, lines: ["hello", "world"])
end

test "every line back is exit 0, and a line lost is exit 1"
  given = Options(clients: 2, lines: ["a", "b"])
  assert code_of(4, given) == 0
  assert code_of(3, given) == 1
end

verified: types, contracts, tests (2), property (0 seeds), sim (not run)
          proven: not run
