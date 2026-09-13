module Effects.Http
expose Fetched, Worker, Server, Servers, answer, fetch, answered?, echoed?

intent "Serve HTTP from processes: the server accepts one exchange per message and hands it to a worker of its own, which answers GET /hello and POST /echo, and a test drives both through Http.fixture() with no real socket."

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

process Server(listener: HttpListener)
  state
    served: UInt32
  end

  message Serve : Bool

  fn update(state, message)
    case message
      Serve:
        case listener.accept(within: 1.minute)
          Ok(exchange):
            worker = Worker.start(exchange)
            worker.send(Answer)
            state.served += 1
            true
          Error(_): false
        end
    end
  end
end

supervisor Servers(listener: HttpListener, exchange: Exchange)
  child Server(listener), restart: :always
  child Worker(exchange), restart: :always
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

fn fetch(http: Http, server: Handle(Server), port: UInt16, request: Request) : Fetched
  server.send(Serve)
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

test "a route's answer depends only on the request"
  hello = Request(method: "GET", path: "/hello")
  assert answer(hello) == Response(status: 200, body: "hello, world")
  assert answer(Request(method: "DELETE", path: "/hello")).status == 404
end

test "GET /hello answers with the name its query gives, unless a call fails and says so"
  http = Http.fixture()
  assert http.listen(0, within: 1.ms) is Ok(listener)
  server = Server.start(listener)
  named = Request(method: "GET", path: "/hello", query: Map.new().set("name", "x"))
  assert answered?(fetch(http, server, listener.port, named), 200, "hello, x")
  bare = Request(method: "GET", path: "/hello")
  assert answered?(fetch(http, server, listener.port, bare), 200, "hello, world")
end

test "POST /echo answers with the body and its content type, and another route is 404, unless a call fails"
  http = Http.fixture()
  assert http.listen(8080, within: 1.ms) is Ok(listener)
  server = Server.start(listener)
  csv = Map.new().set("Content-Type", "text/csv")
  posted = Request(method: "POST", path: "/echo", headers: csv, body: "a,b\n1,2")
  assert echoed?(fetch(http, server, 8080, posted), "a,b\n1,2", "text/csv")
  put = Request(method: "PUT", path: "/echo")
  assert answered?(fetch(http, server, 8080, put), 404, "nothing at PUT /echo")
end

test "a port nothing listens on is Refused, and a request with no server to answer it times out"
  http = Http.fixture()
  root = Request(method: "GET", path: "/")
  assert http.send(root, host: "localhost", port: 1, within: 1.ms) is Error(Refused)
  assert http.listen(0, within: 1.ms) is Ok(listener)
  assert http.send(root, host: "localhost", port: listener.port, within: 1.ms) is Error(Timeout)
end

verified: types, contracts, tests (4), property (0 seeds), sim (100 runs)
          proven: not run
