module Jobq.Api
expose Routed, Draft, Failure, route, respond, health, bearer, drafted

use Jobq.Board{Command, Outcome, Counts}
use Jobq.Job{Job, State, json_of, queue?, payload?, attempts?, lease_ms?, reason?, token?, state_of, created, leased}

intent "Read an HTTP request into a call on the board, or answer it at once: 404 for a route that does not exist, 405 for a method the route does not have, 401 for a missing, empty, or malformed token, and 400 for a body or a query that is not what the route takes; and write every outcome as its status and JSON."

# Where a request goes: the health counts, a call on the board by the worker the token names, or
# an answer now.
enum Routed
  Checkup
  Asked(worker: String, command: Command)
  Answered(response: Response)
end

# The JSON a create carries.
struct Draft
  queue: String
  payload: String
  max_attempts: UInt64
end

struct Failure
  error: String
end

fn route(request: Request) : Routed
  path = request.path
  return health_route(request) if path == "/health"
  return jobs_route(request) if path == "/jobs"
  parts = path.split("/")
  first = parts.get(1) or ""
  second = parts.get(2) or ""
  third = parts.get(3) or ""
  return member(request, second) if first == "jobs" and second != "" and parts.size == 3
  if first == "jobs" and second != "" and parts.size == 4 and (third == "ack" or third == "fail")
    return settling(request, second, third)
  end
  if first == "queues" and second != "" and parts.size == 4 and third == "lease"
    return leasing(request, second)
  end
  Answered(response: failed(404, "no route #{path}"))
end

fn health_route(request: Request) : Routed
  if request.method == "GET": Checkup else: not_allowed("GET")
end

fn jobs_route(request: Request) : Routed
  return not_allowed("GET, POST") if !["GET", "POST"].contains?(request.method)
  case bearer(request)
    Some(worker):
      if request.method == "GET"
        listing(worker, request.query)
      else
        creating(worker, request.body)
      end
    None: unauthorized()
  end
end

fn member(request: Request, id: String) : Routed
  return not_allowed("GET, DELETE") if !["GET", "DELETE"].contains?(request.method)
  case bearer(request)
    Some(worker):
      command = if request.method == "GET": Fetch(id: id) else: Remove(id: id)
      Asked(worker: worker, command: command)
    None: unauthorized()
  end
end

fn settling(request: Request, id: String, verb: String) : Routed
  return not_allowed("POST") if request.method != "POST"
  case bearer(request)
    Some(worker):
      return Asked(worker: worker, command: Ack(id: id)) if verb == "ack"
      case reason_of(request.body)
        Ok(reason): Asked(worker: worker, command: Fail(id: id, reason: reason))
        Error(why): bad(why)
      end
    None: unauthorized()
  end
end

fn leasing(request: Request, queue: String) : Routed
  return not_allowed("POST") if request.method != "POST"
  case bearer(request)
    Some(worker):
      return bad(queue_rule()) if !queue?(queue)
      case lease_of(request.body)
        Ok(ms): Asked(worker: worker, command: Lease(queue: queue, lease_ms: ms))
        Error(why): bad(why)
      end
    None: unauthorized()
  end
end

# The worker a token names: an authorization header of Bearer, a space, and a token of 1 to 64
# bytes with no space or control character. The scheme's case does not matter.
fn bearer(request: Request) : Option(String)
  header = try request.headers.get("authorization")
  return None if header.slice(0, 7).to_lower != "bearer "
  token = header.slice(7, header.size)
  return None if !token?(token)
  Some(token)
end

fn creating(worker: String, body: String) : Routed
  case drafted(body)
    Ok(draft):
      command = Create(queue: draft.queue, payload: draft.payload, max_attempts: draft.max_attempts)
      Asked(worker: worker, command: command)
    Error(why): bad(why)
  end
end

# A create's body, or why it is not one: not JSON, not an object, a field missing or of the wrong
# shape, or a field that breaks its rule.
fn drafted(text: String) : Result(Draft, String)
  ensures result is Ok(d) implies queue?(d.queue) and payload?(d.payload) and attempts?(d.max_attempts)

  fields = try object_of(text)
  queue = try text_field(fields, "queue")
  payload = try text_field(fields, "payload")
  most = try count_field(fields, "max_attempts")
  return Error(queue_rule()) if !queue?(queue)
  if !payload?(payload)
    return Error("payload must be at most 60 KiB with no control characters but newlines")
  end
  return Error("max_attempts must be a whole number from 1 to 100") if !attempts?(most)
  Ok(Draft(queue: queue, payload: payload, max_attempts: most))
end

fn queue_rule() : String
  "a queue name is 1 to 64 letters, digits, - and _"
end

# A lease's body: empty, or an object whose lease_ms, when it has one, is 100 to 3,600,000.
fn lease_of(text: String) : Result(UInt64, String)
  ensures result is Ok(ms) implies lease_ms?(ms)

  return Ok(30_000) if text.trim == ""
  fields = try object_of(text)
  return Ok(30_000) if !fields.has?("lease_ms")
  ms = try count_field(fields, "lease_ms")
  return Error("lease_ms must be a whole number from 100 to 3600000") if !lease_ms?(ms)
  Ok(ms)
end

fn reason_of(text: String) : Result(String, String)
  ensures result is Ok(reason) implies reason?(reason)

  fields = try object_of(text)
  reason = try text_field(fields, "reason")
  if !reason?(reason)
    return Error("reason must be at most 1 KiB with no control characters but newlines")
  end
  Ok(reason)
end

fn listing(worker: String, query: Map(String, String)) : Routed
  queue = query.get("queue")
  if queue is Some(name)
    return bad(queue_rule()) if !queue?(name)
  end
  case query.get("state")
    Some(name):
      case state_of(name)
        Some(wanted): Asked(worker: worker, command: Listing(queue: queue, wanted: Some(wanted)))
        None: bad("state must be queued, leased, done, or dead")
      end
    None: Asked(worker: worker, command: Listing(queue: queue, wanted: None))
  end
end

fn object_of(text: String) : Result(Map(String, Json), String)
  case Json.decode(text)
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
  case fields.get(name)
    Some(value):
      whole = (value.to_i64 or -1).checked_to_u64
      case whole
        Some(n): Ok(n)
        None: Error("#{name} must be a whole number")
      end
    None: Error("#{name} is missing")
  end
end

# The response to an outcome of the board.
fn respond(outcome: Outcome) : Response
  ensures result.status >= 200 and result.status <= 503

  case outcome
    Made(job): json(201, json_of(job))
    Found(job): json(200, json_of(job))
    Listed(jobs): json(200, "{\"jobs\": [#{String.join(jobs.map(fn(j) json_of(j) end), ", ")}]}")
    Removed | Empty: Response(status: 204, body: "")
    Missing: failed(404, "no such job")
    Conflict(reason): failed(409, reason)
    Unavailable(reason): failed(503, reason)
  end
end

fn health(counts: Counts) : Response
  json(200, Json.encode(counts))
end

fn json(status: UInt16, body: String) : Response
  Response(status: status, headers: Map.new().set("content-type", "application/json"), body: body)
end

fn failed(status: UInt16, reason: String) : Response
  json(status, Json.encode(Failure(error: reason)))
end

fn bad(reason: String) : Routed
  Answered(response: failed(400, reason))
end

fn unauthorized() : Routed
  Answered(response: failed(401, "a request needs authorization: Bearer <token>"))
end

fn not_allowed(methods: String) : Routed
  var response = failed(405, "this route takes #{methods}")
  response.headers = response.headers.set("allow", methods)
  Answered(response: response)
end

fn by(method: String, path: String, body: String) : Request
  Request(method: method, path: path, headers: Map.new().set("authorization", "Bearer ada"),
    body: body)
end

fn status_of(routed: Routed) : UInt16
  case routed
    Answered(response): response.status
    Checkup: 200
    Asked(worker: _, command: _): 0
  end
end

fn asked(routed: Routed) : Option(Command)
  case routed
    Asked(worker: _, command: command): Some(command)
    Checkup | Answered(_): None
  end
end

test "each route takes its methods, and any other is 405 with the ones it takes"
  assert route(Request(method: "GET", path: "/health")) == Checkup
  assert status_of(route(by("POST", "/health", ""))) == 405
  assert status_of(route(by("PUT", "/jobs", ""))) == 405
  assert status_of(route(by("POST", "/jobs/j_1", ""))) == 405
  assert status_of(route(by("GET", "/jobs/j_1/ack", ""))) == 405
  assert status_of(route(by("DELETE", "/jobs/j_1/fail", ""))) == 405
  assert route(by("GET", "/queues/q/lease", "")) is Answered(refused)
  assert refused.status == 405 and refused.headers.get("allow") == Some("POST")
end

test "a route that does not exist is 404, whatever its method or token"
  assert status_of(route(by("GET", "/", ""))) == 404
  assert status_of(route(by("GET", "/jobs/", ""))) == 404
  assert status_of(route(by("POST", "/jobs/j_1/done", ""))) == 404
  assert status_of(route(by("POST", "/queues//lease", ""))) == 404
  assert status_of(route(by("POST", "/queues/q/lease/now", ""))) == 404
  assert status_of(route(Request(method: "GET", path: "/job"))) == 404
end

test "a missing, empty, or malformed token is 401, and health needs none"
  assert status_of(route(Request(method: "GET", path: "/jobs"))) == 401
  empty = Request(method: "GET", path: "/jobs", headers: Map.new().set("authorization", "Bearer "))
  assert status_of(route(empty)) == 401
  spaced = Request(method: "POST", path: "/jobs/j_1/ack",
    headers: Map.new().set("authorization", "Bearer a b"))
  assert status_of(route(spaced)) == 401
  basic = Request(method: "GET", path: "/jobs/j_1",
    headers: Map.new().set("authorization", "Basic ada"))
  assert status_of(route(basic)) == 401
  lower = Request(method: "POST", path: "/jobs/j_1/ack",
    headers: Map.new().set("authorization", "bearer bob"))
  assert route(lower) == Asked(worker: "bob", command: Ack(id: "j_1"))
end

test "each route becomes its call"
  post = by("POST", "/jobs", "{\"queue\": \"emails\", \"payload\": \"hi\", \"max_attempts\": 3}")
  assert asked(route(post)) == Some(Create(queue: "emails", payload: "hi", max_attempts: 3))
  assert asked(route(by("GET", "/jobs/j_4", ""))) == Some(Fetch(id: "j_4"))
  assert asked(route(by("DELETE", "/jobs/j_4", ""))) == Some(Remove(id: "j_4"))
  assert asked(route(by("POST", "/jobs/j_4/ack", ""))) == Some(Ack(id: "j_4"))
  fail = by("POST", "/jobs/j_4/fail", "{\"reason\": \"smtp down\"}")
  assert asked(route(fail)) == Some(Fail(id: "j_4", reason: "smtp down"))
  lease = by("POST", "/queues/emails/lease", "{\"lease_ms\": 500}")
  assert asked(route(lease)) == Some(Lease(queue: "emails", lease_ms: 500))
  assert asked(route(by("POST", "/queues/emails/lease", ""))) == Some(Lease(queue: "emails",
    lease_ms: 30_000))
  assert asked(route(by("POST", "/queues/emails/lease", "{}"))) == Some(Lease(queue: "emails",
    lease_ms: 30_000))
  var listing_request = by("GET", "/jobs", "")
  listing_request.query = Map.new().set("queue", "emails").set("state", "dead")
  assert asked(route(listing_request)) == Some(Listing(queue: Some("emails"), wanted: Some(Dead)))
  assert asked(route(by("GET", "/jobs", ""))) == Some(Listing(queue: None, wanted: None))
end

test "a body or query that is not JSON, not an object, missing a field, or of the wrong shape is 400 with why"
  assert drafted("{\"queue\": \"q\"") == Error("the body is not JSON")
  assert drafted("[1]") == Error("the body must be a JSON object")
  assert drafted("{\"payload\": \"p\", \"max_attempts\": 1}") == Error("queue is missing")
  assert drafted("{\"queue\": \"q\", \"payload\": 1, \"max_attempts\": 1}") == Error("payload must be a string")
  assert drafted("{\"queue\": \"q\", \"payload\": \"p\", \"max_attempts\": 1.5}") == Error("max_attempts must be a whole number")
  assert drafted("{\"queue\": \"q\", \"payload\": \"p\", \"max_attempts\": 0}") is Error(_)
  assert drafted("{\"queue\": \"a b\", \"payload\": \"p\", \"max_attempts\": 1}") is Error(_)
  assert drafted("{\"queue\": \"q\", \"payload\": \"a\\tb\", \"max_attempts\": 1}") is Error(_)
  assert status_of(route(by("POST", "/queues/emails/lease", "{\"lease_ms\": 99}"))) == 400
  assert status_of(route(by("POST", "/queues/emails/lease", "{\"lease_ms\": \"1s\"}"))) == 400
  assert status_of(route(by("POST", "/queues/two%20words/lease", ""))) == 400
  assert status_of(route(by("POST", "/jobs/j_1/fail", "{}"))) == 400
  var bad_state = by("GET", "/jobs", "")
  bad_state.query = Map.new().set("state", "running")
  assert status_of(route(bad_state)) == 400
end

test "each outcome is its status and its JSON"
  at = Time.from_parts(2026, 9, 14, 9, 0, 0)
  job = created(1, "emails", "hi", 3, at)
  text = json_of(job)
  assert respond(Made(job: job)) == json(201, text)
  assert respond(Found(job: job)) == json(200, text)
  assert respond(Listed(jobs: [job, job])).body == "{\"jobs\": [#{text}, #{text}]}"
  assert respond(Listed(jobs: [])).body == "{\"jobs\": []}"
  assert respond(Removed) == Response(status: 204, body: "")
  assert respond(Empty).status == 204
  assert respond(Missing) == json(404, "{\"error\": \"no such job\"}")
  assert respond(Conflict(reason: "j_1 is leased")).status == 409
  assert respond(Unavailable(reason: "no")).status == 503
  held = leased(job, "ada", 1_000, at)
  assert respond(Found(job: held)).body.contains?("\"worker\": \"ada\"")
  counts = Counts(queued: 1, leased: 2, done: 3, dead: 4, uptime_ms: 50)
  assert health(counts).body == "{\"queued\": 1, \"leased\": 2, \"done\": 3, \"dead\": 4, \"uptime_ms\": 50}"
end

property "any valid payload sent as JSON becomes a create of that payload"
  for payload in any(String), most in any(UInt8) if payload?(payload) and attempts?(most.to_u64)
    body = Json.encode(Draft(queue: "q", payload: payload, max_attempts: most.to_u64))
    command = Create(queue: "q", payload: payload, max_attempts: most.to_u64)
    assert asked(route(by("POST", "/jobs", body))) == Some(command)
  end
end

verified: types, contracts, tests (7), property (200 seeds), sim (not run)
          proven: not run
