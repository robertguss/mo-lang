# run: world
# run: --clients 3 mo lang
module Httpd.Main
expose Options, options, answer, code_of, main

intent "Serve hello over HTTP on a real socket on 127.0.0.1: the runtime serves the listener into an acceptor process, which answers each exchange as it arrives, one request per connection, and client processes send their requests one at a time and print the status and body that came back; httpd serve --port N serves until it is stopped."

struct Options
  serve: Bool
  port: UInt16
  clients: UInt64
  names: List(String)
end

process Acceptor()
  state
    answered: UInt64
    unsent: UInt64
    quiet: UInt64
  end

  message Accepted(exchange: Exchange)
  message Idle

  fn update(state, message)
    case message
      Accepted(exchange):
        if exchange.reply(answer(exchange.request), within: 5_000.ms) is Ok(_)
          state.answered += 1
        else
          state.unsent += 1
        end
      Idle:
        state.quiet += 1
    end
  end
end

process Client(http: Http, port: UInt16, out: Out, name: String)
  state
    trips: UInt64
  end

  message Fetch(names: List(String)) : UInt64

  fn update(state, message)
    case message
      Fetch(names):
        for who in names
          case fetch(http, port, who)
            Ok(response):
              out.write_line("#{name} got #{response.status} #{response.body}")
              state.trips += 1
            Error(e): out.write_line("#{name} failed: #{e}")
          end
        end
        state.trips
    end
  end
end

supervisor Hellos(http: Http, out: Out)
  child Acceptor, restart: :always
  child Client(http, 0, out, "client"), restart: :always
end

fn options(args: List(String)) : Options
  if args.first == Some("serve")
    port = ((args.get(2) or "0").to_u64 or 0).checked_to_u16 or 0
    return Options(serve: true, port: port, clients: 0, names: [])
  end
  if args.first == Some("--clients")
    n = (args.get(1) or "1").to_u64 or 1
    return Options(serve: false, port: 0, clients: n, names: args.drop(2))
  end
  Options(serve: false, port: 0, clients: 1, names: args)
end

fn answer(request: Request) : Response
  if request.method == "GET" and request.path == "/hello"
    name = request.query.get("name") or "world"
    return Response(status: 200, body: "hello, #{name}")
  end
  Response(status: 404, body: "no #{request.method} #{request.path} here")
end

fn fetch(http: Http, port: UInt16, who: String) : Result(Response, HttpError)
  request = Request(method: "GET", path: "/hello", query: Map.new().set("name", who))
  http.send(request, host: "127.0.0.1", port: port, within: 5_000.ms)
end

fn run(http: Http, out: Out, given: Options) : Result(UInt64, HttpError)
  listener = try http.listen(0, within: 5_000.ms)
  listener.serve(into: Acceptor.start(), idle: 5_000.ms)
  var trips = 0
  for i in 0..given.clients
    client = Client.start(http, listener.port, out, "client #{i}")
    if client.ask(Fetch(names: given.names), within: 60_000.ms) is Ok(n)
      trips += n
    end
  end
  Ok(trips)
end

fn serve_forever(http: Http, out: Out, port: UInt16) : Result(Bool, HttpError)
  listener = try http.listen(port, within: 5_000.ms)
  listener.serve(into: Acceptor.start(), idle: 60_000.ms)
  out.write_line("serving on 127.0.0.1:#{listener.port}")
  out.flush
  Ok(true)
end

fn started(http: Http, out: Out, given: Options) : Result(Bool, HttpError)
  if given.serve
    return serve_forever(http, out, given.port)
  end
  trips = try run(http, out, given)
  out.write_line("#{trips} round trips over 127.0.0.1")
  Ok(trips == given.clients * given.names.size)
end

# 0 when every request came back, else 1.
fn code_of(whole: Bool) : UInt8
  if whole
    return 0
  end
  1
end

# Serving goes on until httpd is stopped; a run of clients ends the program with exit once they
# are done, since the listener would be served on.
fn main(platform: Platform)
  given = options(platform.args)
  case started(platform.http, platform.stdout, given)
    Ok(whole):
      if !given.serve
        platform.exit(code_of(whole))
      end
    Error(e):
      platform.stderr.write_line("httpd failed: #{e}")
      platform.exit(1)
  end
end

test "--clients takes a count, serve takes a port, and the rest are the names"
  three = Options(serve: false, port: 0, clients: 3, names: ["mo"])
  assert options(["--clients", "3", "mo"]) == three
  assert options(["serve", "--port", "8080"]).port == 8080
  assert options(["a", "b"]).names == ["a", "b"]
end

test "every request back is exit 0, and one lost is exit 1"
  assert code_of(true) == 0
  assert code_of(false) == 1
end

test "hello answers with the name its query gives, and any other request is 404"
  named = Request(method: "GET", path: "/hello", query: Map.new().set("name", "mo"))
  assert answer(named) == Response(status: 200, body: "hello, mo")
  assert answer(Request(method: "POST", path: "/hello")).status == 404
end

verified: types, contracts, tests (3), property (0 seeds), sim (not run)
          proven: not run
