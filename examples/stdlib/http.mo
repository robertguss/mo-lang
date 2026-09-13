module Stdlib.Http
expose Heard, exchanged, request_of, status_of

intent "Read an HTTP request off a connection as a Request: its method, path, decoded query, lower-cased headers, and a body by content-length, or the HttpError that says why it is not one, which the client hears as a status."

struct Heard
  got: Result(Request, HttpError)
  answer: String
end

fn request_of(listener: HttpListener) : Result(Request, HttpError)
  exchange = try listener.accept(within: 1.ms)
  Ok(exchange.request)
end

fn status_of(conn: Conn) : String
  if conn.read_line(within: 1.ms) is Ok(Some(line))
    return line
  end
  ""
end

fn exchanged(net: Net, http: Http, raw: String) : Heard
  if http.listen(0, within: 1.ms) is Ok(listener)
    if net.connect("localhost", listener.port, within: 1.ms) is Ok(conn)
      if conn.write(raw, within: 1.ms) is Ok(_)
        got = request_of(listener)
        return Heard(got: got, answer: status_of(conn))
      end
    end
  end
  Heard(got: Error(Closed), answer: "")
end

test "a request with no body has its method, path, and lower-cased headers, and an empty query and body"
  raw = "GET /hello HTTP/1.1\r\nHost: example.com\r\nX-Trace:  a b \r\n\r\n"
  headers = Map.new().set("host", "example.com").set("x-trace", "a b")
  request = Request(method: "GET", path: "/hello", headers: headers)
  assert exchanged(Net.fixture(), Http.fixture(), raw).got == Ok(request)
end

test "a body is read by its content-length, and a repeated header joins its values"
  raw = "POST /echo HTTP/1.1\r\nContent-Length: 5\r\nAccept: a\r\naccept: b\r\n\r\nhello"
  headers = Map.new().set("content-length", "5").set("accept", "a, b")
  request = Request(method: "POST", path: "/echo", headers: headers, body: "hello")
  assert exchanged(Net.fixture(), Http.fixture(), raw).got == Ok(request)
end

test "a query is split into its keys and values, each decoded"
  raw = "GET /search?q=mo+lang&tag=a%2Fb&&flag&q=again HTTP/1.1\r\n\r\n"
  query = Map.new().set("q", "again").set("tag", "a/b").set("flag", "")
  request = Request(method: "GET", path: "/search", query: query)
  assert exchanged(Net.fixture(), Http.fixture(), raw).got == Ok(request)
end

test "a request that is not HTTP is Malformed or Unsupported, and the client hears why"
  net = Net.fixture()
  http = Http.fixture()
  no_version = exchanged(net, http, "GET /hello\r\n\r\n")
  assert no_version.got == Error(Malformed)
  assert no_version.answer == "HTTP/1.1 400 Bad Request"
  assert exchanged(net, http, "GET /x HTTP/1.1\r\nno colon here\r\n\r\n").got == Error(Malformed)
  assert exchanged(net, http, "GET /x?a=%zz HTTP/1.1\r\n\r\n").got == Error(Malformed)
  chunked = exchanged(net, http, "POST /x HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n")
  assert chunked.got == Error(Unsupported)
  assert chunked.answer == "HTTP/1.1 501 Not Implemented"
end

test "a body or a request line over 1 MiB is TooLarge, and a request cut short times out"
  net = Net.fixture()
  http = Http.fixture()
  big = exchanged(net, http, "POST /x HTTP/1.1\r\nContent-Length: 1048577\r\n\r\n")
  assert big.got == Error(TooLarge)
  assert big.answer == "HTTP/1.1 413 Content Too Large"
  path = "a".repeat(1_048_576)
  assert exchanged(net, http, "GET /#{path} HTTP/1.1\r\n\r\n").got == Error(TooLarge)
  cut = "POST /x HTTP/1.1\r\nContent-Length: 9\r\n\r\nshort"
  assert exchanged(net, http, cut).got == Error(Timeout)
end

verified: types, contracts, tests (5), property (0 seeds), sim (not run)
          proven: not run
