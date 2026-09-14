module Jobq.Api
expose Routed, Failure, route, respond, health, bearer, reason?, created, leasing, failing, listing

use Jobq.Books{Health}
use Jobq.Job{Job, State, queue?, payload?, max_attempts?, lease_ms?, token?, state_named, shown}
use Jobq.Moves{Call, Command, Outcome}

intent "Read an HTTP request into a call on the queue service, or answer it at once: 404 for a route that does not exist, 405 for a method the route lacks, 401 for a missing or empty token, and 400 for a body or a query that is not what the route takes; and write every outcome and the health counts as JSON with its status."

# Where a request goes: the health counts, a call on the service, or an answer now.
enum Routed
  Checkup
  Asked(call: Call)
  Answered(response: Response)
end

struct Failure
  error: String
end

fn route(request: Request) : Routed
  parts = request.path.split("/").drop(1)
  name = parts.first or ""
  if request.path == "/health"
    return Checkup if request.method == "GET"
    return Answered(response: not_allowed("GET"))
  end
  return collection(request) if request.path == "/jobs"
  if parts.size == 2 and name == "jobs" and (parts.get(1) or "") != ""
    return member(request, parts.get(1) or "")
  end
  if parts.size == 3 and name == "jobs" and ["ack", "fail"].contains?(parts.get(2) or "")
    return settling(request, parts.get(1) or "", parts.get(2) or "")
  end
  if parts.size == 3 and name == "queues" and parts.get(2) == Some("lease")
    return lease_route(request, parts.get(1) or "")
  end
  Answered(response: failed(404, "no route #{request.path}"))
end

fn collection(request: Request) : Routed
  return Answered(response: not_allowed("GET, POST")) if !["GET", "POST"].contains?(request.method)
  if request.method == "GET"
    return asked(request, listing(request.query))
  end
  asked(request, created(request.body))
end

fn member(request: Request, id: String) : Routed
  return Answered(response: not_allowed("GET, DELETE")) if !["GET",
    "DELETE"].contains?(request.method)
  if request.method == "GET"
    return asked(request, Ok(Fetch(id: id)))
  end
  asked(request, Ok(Remove(id: id)))
end

fn settling(request: Request, id: String, verb: String) : Routed
  return Answered(response: not_allowed("POST")) if request.method != "POST"
  if verb == "ack"
    return asked(request, Ok(Ack(id: id)))
  end
  asked(request, failing(id, request.body))
end

fn lease_route(request: Request, queue: String) : Routed
  return Answered(response: not_allowed("POST")) if request.method != "POST"
  asked(request, leasing(queue, request.body))
end

# The call a request makes once its token is read: 401 without one, and 400 when its body or
# query is not what the route takes.
fn asked(request: Request, command: Result(Command, String)) : Routed
  case bearer(request)
    Some(worker):
      case command
        Ok(given): Asked(call: Call(worker: worker, command: given))
        Error(reason): Answered(response: failed(400, reason))
      end
    None: Answered(response: failed(401, "a request needs authorization: Bearer <token>"))
  end
end

# The token an authorization header carries after Bearer and a space, the scheme in any case.
fn bearer(request: Request) : Option(String)
  header = try request.headers.get("authorization")
  return None if header.slice(0, 7).to_lower != "bearer "
  token = header.slice(7, header.size).trim
  return None if !token?(token)
  Some(token)
end

fn created(body: String) : Result(Command, String)
  fields = try object_of(body)
  queue = try text_field(fields, "queue")
  payload = try text_field(fields, "payload")
  max = try whole_field(fields, "max_attempts")
  return Error("queue must be 1 to 64 letters, digits, - and _") if !queue?(queue)
  if !payload?(payload)
    return Error("payload must be at most 60 KiB of UTF-8 with no control character but a newline")
  end
  return Error("max_attempts must be a whole number from 1 to 100") if !max_attempts?(max)
  Ok(Create(queue: queue, payload: payload, max_attempts: max))
end

# A lease body is empty, or an object whose lease_ms, 30 seconds when left out, is 100 ms to an
# hour.
fn leasing(queue: String, body: String) : Result(Command, String)
  return Error("a queue name is 1 to 64 letters, digits, - and _") if !queue?(queue)
  return Ok(Lease(queue: queue, lease_ms: 30_000)) if body.trim == ""
  fields = try object_of(body)
  lease_ms = if fields.has?("lease_ms"): try whole_field(fields, "lease_ms") else: 30_000
  return Error("lease_ms must be a whole number from 100 to 3600000") if !lease_ms?(lease_ms)
  Ok(Lease(queue: queue, lease_ms: lease_ms))
end

fn failing(id: String, body: String) : Result(Command, String)
  fields = try object_of(body)
  reason = try text_field(fields, "reason")
  if !reason?(reason)
    return Error("reason must be at most 4 KiB with no control character but a newline")
  end
  Ok(Fail(id: id, reason: reason))
end

# A fail's reason: at most 4 KiB, by the payload's rule for characters.
fn reason?(text: String) : Bool
  text.byte_size <= 4_096 and payload?(text)
end

# A listing's query: queue and state, each optional, each keeping its rule when given.
fn listing(query: Map(String, String)) : Result(Command, String)
  queue = query.get("queue")
  if !queue?(queue or "q")
    return Error("queue must be 1 to 64 letters, digits, - and _")
  end
  status = case query.get("state")
    Some(name): Some(try state_of(name))
    None: None
  end
  Ok(Listing(queue: queue, status: status))
end

fn state_of(name: String) : Result(State, String)
  case state_named(name)
    Some(status): Ok(status)
    None: Error("state must be queued, leased, done, or dead")
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

# A whole number from 0 up; JSON numbers read as floats, so one with a fraction is refused.
fn whole_field(fields: Map(String, Json), name: String) : Result(UInt64, String)
  wrong = "#{name} must be a whole number"
  case fields.get(name)
    Some(Number(value)):
      return Error(wrong) if value.round(0) != value or value < 0.0 or value > 1_000_000_000.0
      case value.to_string(0).to_u64
        Some(n): Ok(n)
        None: Error(wrong)
      end
    Some(_): Error(wrong)
    None: Error("#{name} is missing")
  end
end

# The response to an outcome of the service.
fn respond(outcome: Outcome) : Response
  ensures result.status >= 200 and result.status <= 503

  case outcome
    Made(job): json(201, shown(job))
    Found(job) | Handed(job): json(200, shown(job))
    Listed(jobs): json(200, "{\"jobs\": [#{String.join(jobs.map(fn(job) shown(job) end), ", ")}]}")
    Removed | Empty: Response(status: 204, body: "")
    Missing: failed(404, "no such job")
    Conflict(reason): failed(409, reason)
    Unavailable(reason): failed(503, reason)
  end
end

fn health(counts: Health) : Response
  json(200, Json.encode(counts))
end

fn json(status: UInt16, body: String) : Response
  Response(status: status, headers: Map.new().set("content-type", "application/json"), body: body)
end

fn failed(status: UInt16, reason: String) : Response
  json(status, Json.encode(Failure(error: reason)))
end

fn not_allowed(methods: String) : Response
  var response = failed(405, "this route takes #{methods}")
  response.headers = response.headers.set("allow", methods)
  response
end

fn by(method: String, path: String, body: String) : Request
  Request(method: method, path: path, headers: Map.new().set("authorization", "Bearer ada"),
    body: body)
end

fn status_of(routed: Routed) : UInt16
  case routed
    Answered(response): response.status
    Checkup: 200
    Asked(_): 0
  end
end

fn command_of(routed: Routed) : Option(Command)
  case routed
    Asked(call): Some(call.command)
    Checkup | Answered(_): None
  end
end

fn error_of(routed: Routed) : String
  case routed
    Answered(response): response.body
    Checkup | Asked(_): ""
  end
end

test "each route takes its methods, and any other is 405 with the ones it takes"
  assert route(Request(method: "GET", path: "/health")) == Checkup
  assert status_of(route(by("POST", "/health", ""))) == 405
  assert status_of(route(by("PUT", "/jobs", ""))) == 405
  assert route(by("PATCH", "/jobs/j_1", "")) is Answered(refused)
  assert refused.headers.get("allow") == Some("GET, DELETE")
  assert status_of(route(by("GET", "/jobs/j_1/ack", ""))) == 405
  assert status_of(route(by("DELETE", "/queues/q/lease", ""))) == 405
end

test "a route that does not exist is 404, whatever its method or token"
  assert status_of(route(by("GET", "/", ""))) == 404
  assert status_of(route(by("GET", "/jobs/", ""))) == 404
  assert status_of(route(by("POST", "/jobs/j_1/retry", ""))) == 404
  assert status_of(route(by("POST", "/queues/q", ""))) == 404
  assert status_of(route(Request(method: "GET", path: "/job"))) == 404
end

test "a missing or empty token is 401, and a token names the worker"
  assert status_of(route(Request(method: "GET", path: "/jobs"))) == 401
  empty = Request(method: "GET", path: "/jobs", headers: Map.new().set("authorization", "Bearer "))
  assert status_of(route(empty)) == 401
  basic = Request(method: "GET", path: "/jobs", headers: Map.new().set("authorization", "Basic a"))
  assert status_of(route(basic)) == 401
  lower = Request(method: "POST", path: "/jobs/j_2/ack",
    headers: Map.new().set("authorization", "bearer grace"))
  assert route(lower) == Asked(call: Call(worker: "grace", command: Ack(id: "j_2")))
end

test "each route becomes its call"
  post = by("POST", "/jobs", "{\"queue\": \"emails\", \"payload\": \"hi\", \"max_attempts\": 3}")
  assert command_of(route(post)) == Some(Create(queue: "emails", payload: "hi", max_attempts: 3))
  assert command_of(route(by("GET", "/jobs/j_1", ""))) == Some(Fetch(id: "j_1"))
  assert command_of(route(by("DELETE", "/jobs/j_1", ""))) == Some(Remove(id: "j_1"))
  lease = by("POST", "/queues/emails/lease", "{\"lease_ms\": 1000}")
  assert command_of(route(lease)) == Some(Lease(queue: "emails", lease_ms: 1_000))
  assert command_of(route(by("POST", "/queues/emails/lease", ""))) == Some(Lease(queue: "emails",
    lease_ms: 30_000))
  fail = by("POST", "/jobs/j_4/fail", "{\"reason\": \"smtp down\"}")
  assert command_of(route(fail)) == Some(Fail(id: "j_4", reason: "smtp down"))
  list = Request(method: "GET", path: "/jobs", query: Map.new().set("state", "dead"),
    headers: Map.new().set("authorization", "Bearer ada"))
  assert command_of(route(list)) == Some(Listing(queue: None, status: Some(Dead)))
end

test "a body that is not JSON, a missing field, or a field of the wrong shape is 400 with why"
  assert error_of(route(by("POST", "/jobs", "{"))) == "{\"error\": \"the body is not JSON\"}"
  assert created("[1]") == Error("the body must be a JSON object")
  assert created("{\"payload\": \"\", \"max_attempts\": 1}") == Error("queue is missing")
  assert created("{\"queue\": \"q\", \"payload\": 7, \"max_attempts\": 1}") == Error("payload must be a string")
  assert created("{\"queue\": \"q\", \"payload\": \"\", \"max_attempts\": 1.5}") is Error(_)
  assert created("{\"queue\": \"q\", \"payload\": \"\", \"max_attempts\": 0}") is Error(_)
  assert created("{\"queue\": \"a b\", \"payload\": \"\", \"max_attempts\": 1}") is Error(_)
  assert created("{\"queue\": \"q\", \"payload\": \"a\\tb\", \"max_attempts\": 1}") is Error(_)
  assert leasing("q", "{\"lease_ms\": 99}") is Error(_)
  assert leasing("q", "{\"lease_ms\": \"1000\"}") is Error(_)
  assert leasing("a.b", "") is Error(_)
  assert failing("j_1", "{}") == Error("reason is missing")
  assert failing("j_1", "{\"reason\": \"#{"x".repeat(4_097)}\"}") is Error(_)
  assert listing(Map.new().set("state", "gone")) is Error(_)
  assert listing(Map.new().set("queue", "")) is Error(_)
  assert status_of(route(by("POST", "/jobs", "{"))) == 400
end

test "each outcome is its status and its JSON"
  at = Time.fixture()
  kept = Job(number: 1, queue: "q", state: Queued, payload: "p", attempts: 0, max_attempts: 1,
    created_at: at, updated_at: at, worker: None, lease_until: None, reason: None)
  assert respond(Made(job: kept)) == json(201, shown(kept))
  assert respond(Found(job: kept)).status == 200 and respond(Handed(job: kept)).status == 200
  assert respond(Listed(jobs: [kept, kept])).body == "{\"jobs\": [#{shown(kept)}, #{shown(kept)}]}"
  assert respond(Listed(jobs: [])).body == "{\"jobs\": []}"
  assert respond(Removed) == Response(status: 204, body: "")
  assert respond(Empty).status == 204
  assert respond(Missing) == json(404, "{\"error\": \"no such job\"}")
  assert respond(Conflict(reason: "leased")).status == 409
  assert respond(Unavailable(reason: "down")).status == 503
  counts = Health(queued: 1, leased: 2, done: 3, dead: 4, uptime_ms: 5)
  assert health(counts).body == "{\"queued\": 1, \"leased\": 2, \"done\": 3, \"dead\": 4, \"uptime_ms\": 5}"
end

property "any valid payload sent as JSON becomes a create of that payload"
  for payload in any(String) if payload?(payload)
    body = "{\"queue\": \"q\", \"payload\": #{Json.encode(payload)}, \"max_attempts\": 2}"
    made = command_of(route(by("POST", "/jobs", body)))
    assert made == Some(Create(queue: "q", payload: payload, max_attempts: 2))
  end
end

verified: types, contracts, tests (7), property (200 seeds), sim (not run)
          proven: not run
