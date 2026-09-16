module Ledger.Check
expose Trip, trip_of, client, request_of, checked, steady, said_unreached

intent "The ledger's client and its check: a request as the command line or a script line gives it (a token, a method, a path, any JSON, and a key after --key), sent over HTTP and printed as its status and body; a script played line by line against a ledger, with `wait N` letting N milliseconds pass and <today> standing for the clock's day, and the transcript printed with what depends on the clock steadied."

# One request from the client: where to, the token (- for none), the request, and the
# idempotency key ("" for none).
struct Trip
  host: String
  port: UInt16
  token: String
  method: String
  path: String
  json: String
  key: String
end

# A token, a method, a path, any JSON after them joined by spaces as they were split, and a key
# after --key at the end.
fn trip_of(words: List(String), host: String, port: UInt16) : Option(Trip)
  return None if words.size < 3
  var rest = words.drop(3)
  var key = ""
  if rest.size >= 2 and rest.get(rest.size - 2) == Some("--key")
    key = rest.last or ""
    rest = rest.take(rest.size - 2)
  end
  Some(Trip(host: host, port: port, token: words.first or "", method: words.get(1) or "",
    path: words.get(2) or "", json: String.join(rest, " "), key: key))
end

# The response printed, or None when no ledger answered.
fn client(http: Http, trip: Trip) : Option(String)
  case http.send(request_of(trip), host: trip.host, port: trip.port, within: 30_000.ms)
    Ok(response): Some(shown(response))
    Error(_): None
  end
end

fn said_unreached(host: String, port: UInt16) : String
  "no ledger answered at #{host}:#{port}"
end

fn request_of(trip: Trip) : Request
  bearing = if trip.token == "-"
    Map.new()
  else
    Map.new().set("authorization", "Bearer #{trip.token}")
  end
  headers = if trip.key == "": bearing else: bearing.set("idempotency-key", trip.key)
  Request(method: trip.method, path: bare(trip.path), query: query_of(trip.path), headers: headers,
    body: trip.json)
end

# The query a path's ? starts, as key=value pairs split at &.
fn query_of(path: String) : Map(String, String)
  case path.index_of("?")
    Some(at):
      pairs = path.slice(at + 1, path.size).split("&")
      pairs.reduce(Map.new(), fn(query, pair) with_pair(query, pair) end)
    None: Map.new()
  end
end

fn with_pair(query: Map(String, String), pair: String) : Map(String, String)
  return query if pair == ""
  case pair.index_of("=")
    Some(at): query.set(pair.slice(0, at), pair.slice(at + 1, pair.size))
    None: query.set(pair, "")
  end
end

fn bare(path: String) : String
  case path.index_of("?")
    Some(at): path.slice(0, at)
    None: path
  end
end

fn shown(response: Response) : String
  return "#{response.status}\n" if response.body == ""
  "#{response.status} #{response.body}\n"
end

# Each line of the script sent as a request of its own, or a wait, and what came back steadied.
fn checked(http: Http, clock: Clock, port: UInt16, script: List(String)) : String
  today = clock.now.to_iso8601.slice(0, 10)
  var transcript = ""
  for line in script
    transcript = "#{transcript}> #{line}\n#{sent_line(http, port, line, today)}"
  end
  transcript
end

# A wait: the check sends a request to a listener of its own that nothing ever accepts, which
# times out after N milliseconds.
fn napped(http: Http, line: String) : String
  ms = (line.split(" ").get(1) or "").to_u64 or 0
  waited = "waited #{ms} ms\n"
  case http.listen(0, within: 5_000.ms)
    Ok(listener):
      case http.send(Request(method: "GET", path: "/"), host: "127.0.0.1", port: listener.port,
        within: ms.ms)
        Ok(_): waited
        Error(_): waited
      end
    Error(_): waited
  end
end

fn sent_line(http: Http, port: UInt16, line: String, today: String) : String
  return napped(http, line) if line.starts_with?("wait ")
  case trip_of(line.replace("<today>", today).split(" "), "127.0.0.1", port)
    Some(trip):
      case client(http, trip)
        Some(text): steady(text, today)
        None: "#{said_unreached("127.0.0.1", port)}\n"
      end
    None: "a request is a token, a method, a path, and any JSON after them\n"
  end
end

# A transcript with what depends on the clock replaced: every time, the uptime, and the day.
fn steady(text: String, today: String) : String
  times = masked(masked(text, "at", true), "expires_at", true)
  made = masked(masked(times, "created_at", true), "uptime_ms", false)
  made.replace(today, "<today>")
end

fn masked(text: String, key: String, quoted: Bool) : String
  needle = "\"#{key}\": "
  case text.index_of(needle)
    Some(at):
      rest = after_value(text.slice(at + needle.size, text.size), quoted)
      shown_as = if quoted: "\"<#{key}>\"" else: "<#{key}>"
      "#{text.slice(0, at)}#{needle}#{shown_as}#{masked(rest, key, quoted)}"
    None: text
  end
end

fn after_value(piece: String, quoted: Bool) : String
  if quoted
    tail = piece.slice(1, piece.size)
    at = tail.index_of("\"") or 0
    return tail.slice(at + 1, tail.size)
  end
  ends = found(piece.index_of(",")).concat(found(piece.index_of("}")))
  piece.slice(ends.min or piece.size, piece.size)
end

fn found(at: Option(UInt64)) : List(UInt64)
  case at
    Some(n): [n]
    None: []
  end
end

test "a request carries its token, its key, and its query, and a response prints as its status and body"
  trip = Trip(host: "h", port: 1, token: "ada", method: "GET",
    path: "/entries?account=a_1&kind=hold", json: "", key: "")
  asked = request_of(trip)
  assert asked.path == "/entries" and asked.query.get("kind") == Some("hold")
  assert asked.headers.get("authorization") == Some("Bearer ada") and !asked.headers.has?("idempotency-key")
  var keyed = trip
  keyed.token = "-"
  keyed.key = "t1"
  assert request_of(keyed).headers == Map.new().set("idempotency-key", "t1")
  assert shown(Response(status: 201, body: "{}")) == "201 {}\n" and shown(Response(status: 204,
    body: "")) == "204\n"
end

test "a script line takes a key after --key, and its JSON joins back as it was split"
  words = ["ada", "POST", "/transfers", "{\"amount\":", "5}", "--key", "t1"]
  assert trip_of(words, "h",
    1) == Some(Trip(host: "h", port: 1, token: "ada", method: "POST", path: "/transfers",
    json: "{\"amount\": 5}", key: "t1"))
  assert trip_of(["-", "GET", "/health"], "h", 1).map(fn(t) t.key end) == Some("")
  assert trip_of(["ada", "GET"], "h", 1) is None
end

test "the clock's numbers and the day are steadied, and nothing else"
  entry = "{\"id\": \"e_1\", \"key\": \"k\", \"at\": \"2026-09-14T10:00:00.123Z\", \"expires_at\": \"2026-09-14T10:01:00Z\"}"
  assert steady(entry,
    "2026-09-14") == "{\"id\": \"e_1\", \"key\": \"k\", \"at\": \"<at>\", \"expires_at\": \"<expires_at>\"}"
  assert steady("{\"held\": 0, \"uptime_ms\": 1234}",
    "x") == "{\"held\": 0, \"uptime_ms\": <uptime_ms>}"
  assert steady("{\"error\": \"2026-09-14 was settled by e_9\"}",
    "2026-09-14") == "{\"error\": \"<today> was settled by e_9\"}"
  assert steady("{\"name\": \"flat\"}", "2026-09-14") == "{\"name\": \"flat\"}"
end

verified: types, contracts, tests (3), property (0 seeds), sim (not run)
          proven: not run
