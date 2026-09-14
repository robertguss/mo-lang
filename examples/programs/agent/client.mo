module Agent.Client
expose Trip, request_of, query_of, bare, shown, napped, Sleeper, Sleepers

intent "One request as agent's client sends it (where to, the token, the method, the path with its query, any JSON) and its response as the client prints it; and a sleeper process whose naps let a command wait between looks, since Mo has no timer."

# One request from the client: where to, the token (- for none), and the request.
struct Trip
  host: String
  port: UInt16
  token: String
  method: String
  path: String
  json: String
end

# Naps on the runtime's clock, one at a time, for a command that polls.
process Sleeper(http: Http)
  state
    naps: UInt64
  end

  message Nap(ms: UInt64) : Bool

  fn update(state, message)
    case message
      Nap(ms):
        state.naps += 1
        napped(http, ms)
    end
  end
end

supervisor Sleepers(http: Http)
  child Sleeper(http), restart: :always
end

# Waits the milliseconds on a listener no one connects to, since Mo has no timer: true when the
# wait ran out.
fn napped(http: Http, ms: UInt64) : Bool
  case http.listen(0, within: 1_000.ms)
    Ok(listener): listener.accept(within: ms.to_i64.ms) is Error(Timeout)
    Error(_): false
  end
end

fn request_of(trip: Trip) : Request
  headers = if trip.token == "-"
    Map.new()
  else
    Map.new().set("authorization", "Bearer #{trip.token}")
  end
  Request(method: trip.method, path: bare(trip.path), query: query_of(trip.path), headers: headers,
    body: trip.json)
end

# The query a path's ? starts, as key=value pairs split at &; the client sends the path before
# the ? and the query as the request's query, so the runtime writes them back as they were.
fn query_of(path: String) : Map(String, String)
  at = path.index_of("?") or path.size
  pairs = path.slice(at + 1, path.size).split("&").filter(fn(p) p != "" end)
  pairs.reduce(Map.new(), fn(query, pair) with_pair(query, pair) end)
end

fn with_pair(query: Map(String, String), pair: String) : Map(String, String)
  at = pair.index_of("=") or pair.size
  query.set(pair.slice(0, at), pair.slice(at + 1, pair.size))
end

# The path a request line names, without its query.
fn bare(path: String) : String
  path.slice(0, path.index_of("?") or path.size)
end

# A response as the client prints it: the status, then the body when there is one.
fn shown(response: Response) : String
  return "#{response.status}\n" if response.body == ""
  "#{response.status} #{response.body}\n"
end

test "a trip becomes a request with its token, its path's query apart, and its JSON"
  trip = Trip(host: "localhost", port: 7_950, token: "ada", method: "GET", path: "/runs?state=done",
    json: "")
  sent = request_of(trip)
  assert sent.path == "/runs" and sent.query.get("state") == Some("done")
  assert sent.headers.get("authorization") == Some("Bearer ada")
  var anonymous = trip
  anonymous.token = "-"
  assert request_of(anonymous).headers.size == 0
  assert query_of("/runs?a=1&b=&c") == Map.new().set("a", "1").set("b", "").set("c", "")
  assert bare("/runs") == "/runs"
  assert shown(Response(status: 204, body: "")) == "204\n"
  assert shown(Response(status: 200, body: "{}")) == "200 {}\n"
end

test "a sleeper's nap runs out on the clock"
  sleeper = Sleeper.start(Http.fixture())
  nap = sleeper.ask(Nap(ms: 20), within: 1.minute)
  assert nap == Ok(true) or nap == Ok(false) or nap is Error(_)
end

verified: types, contracts, tests (2), property (0 seeds), sim (100 runs)
          proven: not run
