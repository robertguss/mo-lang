module Jobq.Client
expose Trip, trip_of, request_of, shown, asked

intent "Send one request to a jobq and say what came back: a token (- for none), a method, a path, and any JSON after it, joined by spaces as it was split; the answer is its status, then its body when there is one."

# One request: where to, the token (- for none), and the request.
struct Trip
  host: String
  port: UInt16
  token: String
  method: String
  path: String
  json: String
end

fn trip_of(words: List(String), host: String, port: UInt16) : Result(Trip, String)
  return Error("a request is a token, a method, a path, and any JSON") if words.size < 3
  Ok(Trip(host: host, port: port, token: words.first or "", method: words.get(1) or "",
    path: words.get(2) or "", json: String.join(words.drop(3), " ")))
end

fn request_of(trip: Trip) : Request
  headers = if trip.token == "-"
    Map.new()
  else
    Map.new().set("authorization", "Bearer #{trip.token}")
  end
  Request(method: trip.method, path: trip.path, headers: headers, body: trip.json)
end

# A response as the client prints it: the status, then the body when there is one.
fn shown(response: Response) : String
  return "#{response.status}\n" if response.body == ""
  "#{response.status} #{response.body}\n"
end

# The answer as printed, or why no jobq answered. 70 seconds outlasts the server's ask of the queue
# (60) and its reply (10).
fn asked(http: Http, trip: Trip) : Result(String, String)
  case http.send(request_of(trip), host: trip.host, port: trip.port, within: 70_000.ms)
    Ok(response): Ok(shown(response))
    Error(_): Error("no jobq answered at #{trip.host}:#{trip.port}")
  end
end

test "a request is a token, a method, a path, and the JSON after them joined back by spaces"
  words = ["ada", "POST", "/jobs", "{\"queue\":", "\"emails\"}"]
  trip = Trip(host: "localhost", port: 7_900, token: "ada", method: "POST", path: "/jobs",
    json: "{\"queue\": \"emails\"}")
  assert trip_of(words, "localhost", 7_900) == Ok(trip)
  assert trip_of(["ada", "GET"], "localhost", 7_900) is Error(_)
  assert request_of(trip).headers.get("authorization") == Some("Bearer ada")
  var anonymous = trip
  anonymous.token = "-"
  assert request_of(anonymous).headers.size == 0
  assert shown(Response(status: 204, body: "")) == "204\n"
  assert shown(Response(status: 404, body: "{}")) == "404 {}\n"
end

test "a client with no server to answer it says so"
  trip = Trip(host: "localhost", port: 1, token: "ada", method: "GET", path: "/jobs", json: "")
  assert asked(Http.fixture(), trip) == Error("no jobq answered at localhost:1")
end
