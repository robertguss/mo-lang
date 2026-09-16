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
  # body gone; regenerate
end

# The response printed, or None when no ledger answered.
fn client(http: Http, trip: Trip) : Option(String)
  # body gone; regenerate
end

fn said_unreached(host: String, port: UInt16) : String
  # body gone; regenerate
end

fn request_of(trip: Trip) : Request
  # body gone; regenerate
end

# The query a path's ? starts, as key=value pairs split at &.
fn query_of(path: String) : Map(String, String)
  # body gone; regenerate
end

fn with_pair(query: Map(String, String), pair: String) : Map(String, String)
  # body gone; regenerate
end

fn bare(path: String) : String
  # body gone; regenerate
end

fn shown(response: Response) : String
  # body gone; regenerate
end

# Each line of the script sent as a request of its own, or a wait, and what came back steadied.
fn checked(http: Http, clock: Clock, port: UInt16, script: List(String)) : String
  # body gone; regenerate
end

# A wait: the check sends a request to a listener of its own that nothing ever accepts, which
# times out after N milliseconds.
fn napped(http: Http, line: String) : String
  # body gone; regenerate
end

fn sent_line(http: Http, port: UInt16, line: String, today: String) : String
  # body gone; regenerate
end

# A transcript with what depends on the clock replaced: every time, the uptime, and the day.
fn steady(text: String, today: String) : String
  # body gone; regenerate
end

fn masked(text: String, key: String, quoted: Bool) : String
  # body gone; regenerate
end

fn after_value(piece: String, quoted: Bool) : String
  # body gone; regenerate
end

fn found(at: Option(UInt64)) : List(UInt64)
  # body gone; regenerate
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
