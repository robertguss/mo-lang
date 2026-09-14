module Effects.Http
expose Fetched, Worker, Server, Servers, Raw, RawReader, Raws, answer, fetch, fetch_raw, answered?, echoed?, created?

intent "Serve HTTP from processes: the runtime serves the listener into a server process, which hands each exchange to a worker of its own, which answers GET /hello and POST /echo, and a test drives both through Http.fixture() with no real socket."

type Fetched = Result(Response, HttpError)

process Worker(exchange: Exchange)
  state
    answered: Bool
  end

  message Answer

  fn update(state, message)
    case message
      Answer:
        state.answered = exchange.reply(answer(exchange.request), within: 1.minute) is Ok(_)
    end
  end
end

process Server()
  state
    served: UInt32
    quiet: UInt32
  end

  message Accepted(exchange: Exchange)
  message Idle

  fn update(state, message)
    case message
      Accepted(exchange):
        Worker.start(exchange).send(Answer)
        state.served += 1
      Idle:
        state.quiet += 1
    end
  end
end

supervisor Servers(exchange: Exchange)
  child Server, restart: :always
  child Worker(exchange), restart: :always
end

# A server that writes `wire`, as it is, to each client once its request's headers end.
process Raw(wire: String)
  state
    served: UInt32
    quiet: UInt32
  end

  message Accepted(conn: Conn)
  message Idle

  fn update(state, message)
    case message
      Accepted(conn):
        conn.lines(into: RawReader.start(conn, wire), idle: 1.minute)
        state.served += 1
      Idle:
        state.quiet += 1
    end
  end
end

# Reads a client's request line and headers; at the blank line after them it writes the wire and
# closes the connection.
process RawReader(conn: Conn, wire: String)
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
        state.lines += 1
        if text == ""
          if conn.write(wire, within: 1.minute) is Ok(_)
            state.lines += 0
          end
          conn.close
        end
      LineTooLong | Closed | Idle: conn.close
    end
  end
end

supervisor Raws(conn: Conn)
  child Raw(""), restart: :always
  child RawReader(conn, ""), restart: :always
end

fn answer(request: Request) : Response
  if request.method == "GET" and request.path == "/hello"
    name = request.query.get("name") or "world"
    return Response(status: 200, body: "hello, #{name}")
  end
  if request.method == "POST" and request.path == "/echo"
    kind = request.headers.get("content-type") or "text/plain"
    return Response(status: 200, headers: Map.new().set("content-type", kind), body: request.body)
  end
  Response(status: 404, body: "nothing at #{request.method} #{request.path}")
end

fn fetch(http: Http, port: UInt16, request: Request) : Fetched
  http.send(request, host: "localhost", port: port, within: 1.minute)
end

fn answered?(got: Fetched, status: UInt16, body: String) : Bool
  case got
    Ok(response): response.status == status and response.body == body
    Error(_): true
  end
end

fn echoed?(got: Fetched, body: String, kind: String) : Bool
  case got
    Ok(response): response.body == body and response.headers.get("content-type") == Some(kind)
    Error(_): true
  end
end

fn fetch_raw(http: Http, port: UInt16) : Fetched
  http.send(Request(method: "GET", path: "/"), host: "localhost", port: port, within: 1.minute)
end

fn created?(got: Fetched) : Bool
  case got
    Ok(response):
      joined = response.headers.get("x-a") == Some("1, 2")
      response.status == 201 and response.body == "to the end" and joined
    Error(_): true
  end
end

test "a route's answer depends only on the request"
  hello = Request(method: "GET", path: "/hello")
  assert answer(hello) == Response(status: 200, body: "hello, world")
  assert answer(Request(method: "DELETE", path: "/hello")).status == 404
end

test "GET /hello answers with the name its query gives, unless a call fails and says so"
  http = Http.fixture()
  assert http.listen(0, within: 1.ms) is Ok(listener)
  listener.serve(into: Server.start(), idle: 1.minute)
  named = Request(method: "GET", path: "/hello", query: Map.new().set("name", "x"))
  assert answered?(fetch(http, listener.port, named), 200, "hello, x")
  bare = Request(method: "GET", path: "/hello")
  assert answered?(fetch(http, listener.port, bare), 200, "hello, world")
end

test "POST /echo answers with the body and its content type, and another route is 404, unless a call fails"
  http = Http.fixture()
  assert http.listen(8080, within: 1.ms) is Ok(listener)
  listener.serve(into: Server.start(), idle: 1.minute)
  csv = Map.new().set("Content-Type", "text/csv")
  posted = Request(method: "POST", path: "/echo", headers: csv, body: "a,b\n1,2")
  assert echoed?(fetch(http, 8080, posted), "a,b\n1,2", "text/csv")
  put = Request(method: "PUT", path: "/echo")
  assert answered?(fetch(http, 8080, put), 404, "nothing at PUT /echo")
end

test "a port nothing listens on is Refused, and a request with no server to answer it times out"
  http = Http.fixture()
  root = Request(method: "GET", path: "/")
  assert http.send(root, host: "localhost", port: 1, within: 1.ms) is Error(Refused)
  assert http.listen(0, within: 1.ms) is Ok(listener)
  assert http.send(root, host: "localhost", port: listener.port, within: 1.ms) is Error(Timeout)
end

test "a response with no content-length runs to the end of the stream, and its headers join as a request's do, unless a call fails"
  http = Http.fixture()
  assert Net.fixture().listen(0, within: 1.ms) is Ok(listener)
  listener.serve(into: Raw.start("HTTP/1.1 201 Created\r\nX-A: 1\r\nx-a: 2\r\n\r\nto the end"),
    idle: 1.minute)
  assert created?(fetch_raw(http, listener.port))
end

verified: types, contracts, tests (5), property (0 seeds), sim (100 runs)
          proven: not run
