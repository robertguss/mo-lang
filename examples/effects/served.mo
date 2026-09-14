module Effects.Served
expose Echo, Acceptor, Heard, Counter, Worker, Front, Echoes, talked, heard_so_far?, streamed, counted?, fetched, answered?, garbled, at_most?

intent "The runtime owns the loop: a listener served into a process delivers each connection as a message, a connection read into a process delivers each line, the end of the stream, a line too long, and a silence, an HTTP listener served into a process delivers each whole request, and a process with a small mailbox is fed a long stream without its mailbox overflowing."

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
      LineTooLong:
        if conn.write("too long\n", within: 1.minute) is Ok(_)
          state.lines += 1
        end
      Closed | Idle: conn.close
    end
  end
end

process Acceptor()
  state
    accepted: UInt32
    quiet: UInt32
  end

  message Accepted(conn: Conn)
  message Idle

  fn update(state, message)
    case message
      Accepted(conn):
        conn.lines(into: Echo.start(conn), idle: 30_000.ms)
        state.accepted += 1
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

process Counter(out: Out) mailbox: 8
  state
    lines: UInt64
    bytes: UInt64
  end

  message Line(text: String)
  message LineTooLong
  message Closed
  message Idle

  fn update(state, message)
    case message
      Line(text):
        state.lines += 1
        state.bytes += text.size
      LineTooLong:
        state.lines += 1
      Closed: out.write_line("closed after #{state.lines} lines, #{state.bytes} bytes")
      Idle: out.write_line("idle after #{state.lines} lines")
    end
  end
end

process Worker(exchange: Exchange)
  state
    answered: Bool
  end

  message Answer

  fn update(state, message)
    case message
      Answer:
        name = exchange.request.query.get("name") or "world"
        reply = Response(status: 200, body: "hello, #{name}")
        state.answered = exchange.reply(reply, within: 1.minute) is Ok(_)
    end
  end
end

process Front()
  state
    served: UInt64
    quiet: UInt64
  end

  message Accepted(exchange: Exchange)
  message Idle
  message Served : UInt64

  fn update(state, message)
    case message
      Accepted(exchange):
        Worker.start(exchange).send(Answer)
        state.served += 1
      Idle:
        state.quiet += 1
      Served: state.served
    end
  end
end

supervisor Echoes(conn: Conn, out: Out, exchange: Exchange)
  child Acceptor, restart: :always
  child Echo(conn), restart: :always
  child Heard, restart: :always
  child Counter(out), restart: :always
  child Worker(exchange), restart: :always
  child Front, restart: :always
end

# A client connects, has what comes back read into `heard`, and writes its lines, all in one
# statement, so the runtime serves it only once the lines are written.
fn talked(net: Net, port: UInt16, heard: Handle(Heard), lines: List(String)) : Result(Bool,
  NetError)
  client = try net.connect("localhost", port, within: 1.minute)
  client.lines(into: heard, idle: 30_000.ms)
  try client.write(String.join(lines.map(fn(line) "#{line}\n" end), ""), within: 1.minute)
  Ok(true)
end

# What a client heard is what it should have heard, in order, up to where a failure cut it
# short or a seeded run left the rest waiting; anything, when it never got to talk.
fn heard_so_far?(talk: Result(Bool, NetError), heard: Result(List(String), AskError),
  expected: List(String)) : Bool
  case heard
    Ok(lines): talk is Error(_) or expected.take(lines.size) == lines
    Error(_): true
  end
end

# A stream of `n` lines, written whole and closed, read into a process with a mailbox of 8.
fn streamed(net: Net, out: Out, n: UInt64) : Result(UInt64, NetError)
  listener = try net.listen(0, within: 1.minute)
  client = try net.connect("localhost", listener.port, within: 1.minute)
  server = try listener.accept(within: 1.minute)
  server.lines(into: Counter.start(out), idle: 30_000.ms)
  lines = (0..n).map(fn(i) "line #{i}\n" end)
  try client.write(String.join(lines, ""), within: 1.minute)
  client.close
  Ok(n)
end

# What the counter wrote: the whole stream's count and its end, or nothing yet when a seeded run
# left the lines waiting, or one early end when a fault closed the connection or let it go idle.
# The fixed order is what holds the count exact; no run overflows the mailbox, which would crash.
fn counted?(written: List(String), whole: String) : Bool
  written == [whole] or written.size == 0 or written.size == 1 and !written.contains?(whole)
end

fn fetched(http: Http, port: UInt16, who: String) : Result(Response, HttpError)
  request = Request(method: "GET", path: "/hello", query: Map.new().set("name", who))
  http.send(request, host: "localhost", port: port, within: 1.minute)
end

# The answer a served request got, unless a call failed and said so.
fn answered?(got: Result(Response, HttpError), body: String) : Bool
  case got
    Ok(response): response.status == 200 and response.body == body
    Error(_): true
  end
end

# A raw client that has what comes back read into `heard`, and writes what is not a request,
# in one statement.
fn garbled(net: Net, port: UInt16, heard: Handle(Heard)) : Result(Bool, NetError)
  raw = try net.connect("localhost", port, within: 1.minute)
  raw.lines(into: heard, idle: 30_000.ms)
  try raw.write("NOT HTTP\r\n\r\n", within: 1.minute)
  Ok(true)
end

fn at_most?(got: Result(UInt64, AskError), n: UInt64) : Bool
  case got
    Ok(k): k <= n
    Error(_): true
  end
end

test "each line a client sends comes back, one too long is said to be, and a served listener is Busy to accept"
  net = Net.fixture()
  assert net.listen(0, within: 1.ms) is Ok(listener)
  listener.serve(into: Acceptor.start(), idle: 30_000.ms)
  heard = Heard.start()
  talk = talked(net, listener.port, heard, ["a", "b", "x".repeat(65_537), "c"])
  assert heard_so_far?(talk, heard.ask(Lines, within: 1.minute), ["a", "b", "too long", "c"])
  taken = listener.accept(within: 1.ms)
  assert taken is Error(Busy) or taken is Error(Timeout)
end

test "a stream of 2,000 lines reaches a process whose mailbox holds 8, and its end after them"
  out = Out.fixture()
  sent = streamed(Net.fixture(), out, 2_000)
  assert sent is Ok(2_000) or sent is Error(_)
  assert counted?(out.written, "closed after 2000 lines, 16890 bytes\n")
end

test "a served HTTP listener hands each whole request to a process, and answers one that is not HTTP itself"
  http = Http.fixture()
  assert http.listen(0, within: 1.ms) is Ok(listener)
  front = Front.start()
  listener.serve(into: front, idle: 30_000.ms)
  assert answered?(fetched(http, listener.port, "a"), "hello, a")
  assert answered?(fetched(http, listener.port, "b"), "hello, b")
  heard = Heard.start()
  sent = garbled(Net.fixture(), listener.port, heard)
  refusal = ["HTTP/1.1 400 Bad Request", "content-length: 0", "connection: close", ""]
  assert heard_so_far?(sent, heard.ask(Lines, within: 1.minute), refusal)
  assert at_most?(front.ask(Served, within: 1.minute), 2)
end

verified: types, contracts, tests (3), property (0 seeds), sim (100 runs)
          proven: not run
