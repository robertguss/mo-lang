module Jobq.Api
expose Routed, route, respond, bearer, created_from, lease_from, fail_from, listing_from

use Jobq.Board{Command, Call, Outcome, Counts}
use Jobq.Job{Job, queue?, payload?, reason?, token?, attempts?, lease_ms?, phase_named, id_of, shown}

intent "Read an HTTP request into a call on the queue, or answer it at once: 404 for a route that does not exist, 405 for a method the route does not take, 401 for a missing or malformed token, and 400 for a body or a name of the wrong shape; and write every outcome as its status and JSON."

# Where a request goes: a call on the queue, or an answer now.
enum Routed
  Asked(call: Call)
  Answered(response: Response)
end

fn route(request: Request) : Routed
  parts = request.path.split("/")
  case parts.size
    2:
      case parts.get(1) or ""
        "health": healthy(request)
        "jobs": collection(request)
        _: nowhere(request)
      end
    3: if parts.get(1) == Some("jobs") and parts.get(2) != Some("")
      member(request, parts.get(2) or "")
    else
      nowhere(request)
    end
    4:
      case (parts.get(1) or "", parts.get(3) or "")
        ("jobs", "ack"): settling(request, parts.get(2) or "", false)
        ("jobs", "fail"): settling(request, parts.get(2) or "", true)
        ("queues", "lease"): leasing(request, parts.get(2) or "")
        _: nowhere(request)
      end
    _: nowhere(request)
  end
end

fn nowhere(request: Request) : Routed
  Answered(response: failed(404, "no route #{request.path}"))
end

fn healthy(request: Request) : Routed
  return Answered(response: not_allowed("GET")) if request.method != "GET"
  Asked(call: Call(worker: "", command: Health))
end

fn collection(request: Request) : Routed
  return Answered(response: not_allowed("GET, POST")) if !["GET", "POST"].contains?(request.method)
  worker = try_token(request)
  return Answered(response: unauthorized()) if worker == ""
  command = if request.method == "GET": listing_from(request.query) else: created_from(request.body)
  asked(worker, command)
end

fn member(request: Request, id: String) : Routed
  return Answered(response: not_allowed("GET, DELETE")) if !["GET",
    "DELETE"].contains?(request.method)
  worker = try_token(request)
  return Answered(response: unauthorized()) if worker == ""
  command = if request.method == "GET": Fetch(id: id) else: Remove(id: id)
  Asked(call: Call(worker: worker, command: command))
end

fn settling(request: Request, id: String, failing: Bool) : Routed
  return Answered(response: not_allowed("POST")) if request.method != "POST"
  worker = try_token(request)
  return Answered(response: unauthorized()) if worker == ""
  return Asked(call: Call(worker: worker, command: Ack(id: id))) if !failing
  asked(worker, fail_from(id, request.body))
end

fn leasing(request: Request, queue: String) : Routed
  return Answered(response: not_allowed("POST")) if request.method != "POST"
  worker = try_token(request)
  return Answered(response: unauthorized()) if worker == ""
  if !queue?(queue)
    return Answered(response: failed(400, "a queue's name is 1 to 64 letters, digits, - or _"))
  end
  case lease_from(request.body)
    Ok(ms): Asked(call: Call(worker: worker, command: Lease(queue: queue, lease_ms: ms)))
    Error(why): Answered(response: failed(400, why))
  end
end

fn asked(worker: String, command: Result(Command, String)) : Routed
  case command
    Ok(given): Asked(call: Call(worker: worker, command: given))
    Error(why): Answered(response: failed(400, why))
  end
end

fn try_token(request: Request) : String
  bearer(request) or ""
end

# The token an authorization header carries: Bearer, one space, and a token as RFC 6750 spells
# one. The scheme's case does not matter.
fn bearer(request: Request) : Option(String)
  header = try request.headers.get("authorization")
  return None if header.slice(0, 7).to_lower != "bearer "
  token = header.slice(7, header.size)
  return None if !token?(token)
  Some(token)
end

# A create's body: a queue, a payload, and max_attempts, each of its shape.
fn created_from(body: String) : Result(Command, String)
  fields = try object_of(body)
  queue = try text_field(fields, "queue")
  payload = try text_field(fields, "payload")
  max_attempts = try count_field(fields, "max_attempts")
  return Error("queue must be 1 to 64 letters, digits, - or _") if !queue?(queue)
  if !payload?(payload)
    return Error("payload must be at most 60 KiB of text with no control characters but newlines")
  end
  return Error("max_attempts must be a whole number from 1 to 100") if !attempts?(max_attempts)
  Ok(Create(queue: queue, payload: payload, max_attempts: max_attempts))
end

# A lease's body: lease_ms, 30,000 when the body is empty or leaves it out.
fn lease_from(body: String) : Result(UInt64, String)
  ensures result is Ok(ms) implies lease_ms?(ms)

  return Ok(30_000) if body.trim == ""
  fields = try object_of(body)
  return Ok(30_000) if !fields.has?("lease_ms")
  ms = try count_field(fields, "lease_ms")
  return Error("lease_ms must be a whole number from 100 to 3600000") if !lease_ms?(ms)
  Ok(ms)
end

# A fail's body: a reason of at most 4 KiB with no control characters but newlines.
fn fail_from(id: String, body: String) : Result(Command, String)
  fields = try object_of(body)
  reason = try text_field(fields, "reason")
  if !reason?(reason)
    return Error("reason must be at most 4 KiB of text with no control characters but newlines")
  end
  Ok(Fail(id: id, reason: reason))
end

# A listing's query: a queue, a state, both, or neither.
fn listing_from(query: Map(String, String)) : Result(Command, String)
  queue = query.get("queue")
  if queue is Some(name) and !queue?(name)
    return Error("queue must be 1 to 64 letters, digits, - or _")
  end
  case query.get("state")
    Some(name):
      case phase_named(name)
        Some(state): Ok(Listing(queue: queue, state: Some(state)))
        None: Error("state must be queued, leased, done, or dead")
      end
    None: Ok(Listing(queue: queue, state: None))
  end
end

fn object_of(body: String) : Result(Map(String, Json), String)
  case Json.decode(body)
    Ok(Object(fields)): Ok(fields)
    Ok(_): Error("the body must be a JSON object")
    Error(_): Error("the body is not JSON")
  end
end

fn text_field(fields: Map(String, Json), name: String) : Result(String, String)
  case fields.get(name)
    Some(String(text)): Ok(text)
    Some(_): Error("#{name} must be a string")
    None: Error("#{name} is missing")
  end
end

fn count_field(fields: Map(String, Json), name: String) : Result(UInt64, String)
  given = try present(fields, name)
  whole = given.to_i64 or -1
  return Error("#{name} must be a whole number") if whole < 0
  Ok(whole.to_u64)
end

fn present(fields: Map(String, Json), name: String) : Result(Json, String)
  case fields.get(name)
    Some(value): Ok(value)
    None: Error("#{name} is missing")
  end
end

# The response to an outcome of the queue.
fn respond(outcome: Outcome) : Response
  ensures result.status >= 200 and result.status <= 503

  case outcome
    Made(one): json(201, shown(one))
    Found(one): json(200, shown(one))
    Listed(jobs): json(200, "{\"jobs\": [#{String.join(jobs.map(fn(j) shown(j) end), ", ")}]}")
    Removed: Response(status: 204, body: "")
    Missing: failed(404, "no such job")
    Conflict(reason): failed(409, reason)
    Empty: Response(status: 204, body: "")
    Healthy(counts): json(200, health(counts))
    Unavailable(reason): failed(503, reason)
  end
end

fn health(counts: Counts) : String
  "{\"queued\": #{counts.queued}, \"leased\": #{counts.leased}, \"done\": #{counts.done}, \"dead\": #{counts.dead}, \"uptime_ms\": #{counts.uptime_ms}}"
end

fn json(status: UInt16, body: String) : Response
  Response(status: status, headers: Map.new().set("content-type", "application/json"), body: body)
end

fn failed(status: UInt16, reason: String) : Response
  json(status, "{\"error\": #{Json.encode(reason)}}")
end

fn unauthorized() : Response
  failed(401, "a request needs authorization: Bearer <token>")
end

fn not_allowed(methods: String) : Response
  var response = failed(405, "this route takes #{methods}")
  response.headers = response.headers.set("allow", methods)
  response
end

fn by(method: String, path: String, token: String, body: String) : Request
  Request(method: method, path: path, headers: Map.new().set("authorization", "Bearer #{token}"),
    body: body)
end

fn status_of(routed: Routed) : UInt16
  case routed
    Answered(response): response.status
    Asked(_): 0
  end
end

fn command_of(routed: Routed) : Option(Command)
  case routed
    Asked(call): Some(call.command)
    Answered(_): None
  end
end

fn why(routed: Routed) : String
  case routed
    Answered(response): response.body
    Asked(_): ""
  end
end

test "each route takes its methods, and any other is 405 with the ones it takes"
  assert route(Request(method: "GET", path: "/health")) == Asked(call: Call(worker: "",
    command: Health))
  assert status_of(route(Request(method: "POST", path: "/health"))) == 405
  assert status_of(route(by("PUT", "/jobs", "w", ""))) == 405
  assert route(by("PATCH", "/jobs/j_1", "w", "")) is Answered(refused)
  assert refused.headers.get("allow") == Some("GET, DELETE")
  assert status_of(route(by("GET", "/jobs/j_1/ack", "w", ""))) == 405
  assert status_of(route(by("DELETE", "/jobs/j_1/fail", "w", ""))) == 405
  assert status_of(route(by("GET", "/queues/q/lease", "w", ""))) == 405
end

test "a route that does not exist is 404, whatever its method or token"
  assert status_of(route(by("GET", "/", "w", ""))) == 404
  assert status_of(route(by("GET", "/jobs/", "w", ""))) == 404
  assert status_of(route(by("POST", "/jobs/j_1/done", "w", ""))) == 404
  assert status_of(route(by("POST", "/queues/q", "w", ""))) == 404
  assert status_of(route(by("POST", "/queues/q/lease/x", "w", ""))) == 404
  assert status_of(route(Request(method: "GET", path: "/job"))) == 404
end

test "a missing, empty, or malformed token is 401; health needs none, and the scheme's case does not matter"
  assert status_of(route(Request(method: "GET", path: "/jobs"))) == 401
  assert status_of(route(by("GET", "/jobs", "", ""))) == 401
  assert status_of(route(by("GET", "/jobs", "a b", ""))) == 401
  assert status_of(route(by("POST", "/queues/q/lease", "a\"b", ""))) == 401
  basic = Request(method: "GET", path: "/jobs/j_1",
    headers: Map.new().set("authorization", "Basic w"))
  assert status_of(route(basic)) == 401
  lower = Request(method: "GET", path: "/jobs/j_1",
    headers: Map.new().set("authorization", "bearer w-1"))
  assert route(lower) == Asked(call: Call(worker: "w-1", command: Fetch(id: "j_1")))
end

test "each route becomes its call"
  post = by("POST", "/jobs", "p",
    "{\"queue\": \"emails\", \"payload\": \"hi\\n\", \"max_attempts\": 3}")
  assert command_of(route(post)) == Some(Create(queue: "emails", payload: "hi\n", max_attempts: 3))
  listing = Request(method: "GET", path: "/jobs",
    query: Map.new().set("queue", "emails").set("state", "dead"),
    headers: Map.new().set("authorization", "Bearer p"))
  assert command_of(route(listing)) == Some(Listing(queue: Some("emails"), state: Some(Dead)))
  assert command_of(route(by("GET", "/jobs", "p", ""))) == Some(Listing(queue: None, state: None))
  assert command_of(route(by("GET", "/jobs/j_4", "p", ""))) == Some(Fetch(id: "j_4"))
  assert command_of(route(by("DELETE", "/jobs/j_4", "p", ""))) == Some(Remove(id: "j_4"))
  assert command_of(route(by("POST", "/jobs/j_4/ack", "w", "anything"))) == Some(Ack(id: "j_4"))
  fail = by("POST", "/jobs/j_4/fail", "w", "{\"reason\": \"smtp down\"}")
  assert command_of(route(fail)) == Some(Fail(id: "j_4", reason: "smtp down"))
  lease = by("POST", "/queues/emails/lease", "w", "{\"lease_ms\": 100}")
  assert route(lease) == Asked(call: Call(worker: "w",
    command: Lease(queue: "emails", lease_ms: 100)))
  assert command_of(route(by("POST", "/queues/emails/lease", "w",
    ""))) == Some(Lease(queue: "emails",
    lease_ms: 30_000))
  assert command_of(route(by("POST", "/queues/emails/lease", "w",
    "{}"))) == Some(Lease(queue: "emails",
    lease_ms: 30_000))
end

test "a body that is not JSON, not an object, missing a field, or of the wrong shape is 400 with why"
  assert created_from("") == Error("the body is not JSON")
  assert created_from("{\"queue\": \"q\"") == Error("the body is not JSON")
  assert created_from("[1]") == Error("the body must be a JSON object")
  assert created_from("{\"payload\": \"\", \"max_attempts\": 1}") == Error("queue is missing")
  assert created_from("{\"queue\": \"q\", \"max_attempts\": 1}") == Error("payload is missing")
  assert created_from("{\"queue\": \"q\", \"payload\": \"\"}") == Error("max_attempts is missing")
  assert created_from("{\"queue\": 1, \"payload\": \"\", \"max_attempts\": 1}") == Error("queue must be a string")
  assert created_from("{\"queue\": \"q\", \"payload\": null, \"max_attempts\": 1}") == Error("payload must be a string")
  assert created_from("{\"queue\": \"q\", \"payload\": \"\", \"max_attempts\": \"3\"}") == Error("max_attempts must be a whole number")
  assert created_from("{\"queue\": \"q\", \"payload\": \"\", \"max_attempts\": 1.5}") == Error("max_attempts must be a whole number")
  assert created_from("{\"queue\": \"q\", \"payload\": \"\", \"max_attempts\": 0}") is Error(_)
  assert created_from("{\"queue\": \"q\", \"payload\": \"\", \"max_attempts\": 101}") is Error(_)
  assert created_from("{\"queue\": \"a b\", \"payload\": \"\", \"max_attempts\": 1}") is Error(_)
  assert created_from("{\"queue\": \"\", \"payload\": \"\", \"max_attempts\": 1}") is Error(_)
  assert created_from("{\"queue\": \"q\", \"payload\": \"a\\u0007b\", \"max_attempts\": 1}") is Error(_)
  big = "{\"queue\": \"q\", \"payload\": \"#{"x".repeat(61_441)}\", \"max_attempts\": 1}"
  assert created_from(big) is Error(_)
  assert lease_from("{\"lease_ms\": 99}") is Error(_)
  assert lease_from("{\"lease_ms\": 3600001}") is Error(_)
  assert lease_from("{\"lease_ms\": \"100\"}") is Error(_)
  assert lease_from("[]") is Error(_)
  assert lease_from(" 3") is Error(_)
  assert fail_from("j_1", "{}") == Error("reason is missing")
  assert fail_from("j_1", "") == Error("the body is not JSON")
  assert fail_from("j_1", "{\"reason\": 5}") == Error("reason must be a string")
  assert status_of(route(by("POST", "/queues/a%20b/lease", "w", ""))) == 400
  assert status_of(route(by("POST", "/jobs", "w", "{\"queue\": 1}"))) == 400
  assert why(route(by("POST", "/jobs", "w", "nope"))) == "{\"error\": \"the body is not JSON\"}"
  bad_state = Request(method: "GET", path: "/jobs", query: Map.new().set("state", "gone"),
    headers: Map.new().set("authorization", "Bearer p"))
  assert status_of(route(bad_state)) == 400
end

test "each outcome is its status and its JSON"
  at = Time.parse("2026-09-14T10:00:00Z") or Time.from_parts(2026, 1, 1, 0, 0, 0)
  one = Job(number: 1, queue: "q", state: Queued, payload: "p", attempts: 0, max_attempts: 1,
    created_at: at, updated_at: at, worker: None, lease_until: None, reason: None)
  text = "{\"id\": \"j_1\", \"queue\": \"q\", \"state\": \"queued\", \"payload\": \"p\", \"attempts\": 0, \"max_attempts\": 1, \"created_at\": \"2026-09-14T10:00:00Z\", \"updated_at\": \"2026-09-14T10:00:00Z\"}"
  assert respond(Made(job: one)) == json(201, text)
  assert respond(Found(job: one)) == json(200, text)
  assert respond(Listed(jobs: [one, one])).body == "{\"jobs\": [#{text}, #{text}]}"
  assert respond(Listed(jobs: [])).body == "{\"jobs\": []}"
  assert respond(Removed) == Response(status: 204, body: "")
  assert respond(Empty) == Response(status: 204, body: "")
  assert respond(Missing) == json(404, "{\"error\": \"no such job\"}")
  assert respond(Conflict(reason: "j_1 is leased")) == json(409, "{\"error\": \"j_1 is leased\"}")
  assert respond(Unavailable(reason: "the log did not take the change")).status == 503
  counts = Counts(queued: 1, leased: 2, done: 3, dead: 4, uptime_ms: 5)
  assert respond(Healthy(counts: counts)).body == "{\"queued\": 1, \"leased\": 2, \"done\": 3, \"dead\": 4, \"uptime_ms\": 5}"
  assert id_of(one.number) == "j_1"
end

property "any valid payload sent as JSON becomes a create of that payload"
  for payload in any(String) if payload?(payload)
    body = "{\"queue\": \"q\", \"payload\": #{Json.encode(payload)}, \"max_attempts\": 2}"
    assert created_from(body) == Ok(Create(queue: "q", payload: payload, max_attempts: 2))
  end
end

verified: types, contracts, tests (7), property (200 seeds), sim (not run)
          proven: not run
