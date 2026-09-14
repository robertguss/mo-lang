module Agent.Api
expose Want, Command, Routed, Failure, route, respond, health, bearer, order_of

use Agent.Record{Budget, Order, Status, Health, budget, order, record, goal?, folder?, tools?, hosts?, steps?, tokens?, wall_ms?, tool_ms?, token?, status_name, status_named, shown}
use Agent.Shelf{Outcome}

intent "Read an HTTP request into a command on the runs, or answer it at once: 404 for a route that does not exist, 405 for a method the route lacks, 401 for a missing or empty token, and 400 for a body or a query the route does not take; and write each outcome and the health counts as JSON with its status."

# What a client wants of the runs.
enum Want
  WantNew(order: Order)
  WantRun(id: String)
  WantRuns(status: Option(Status))
  WantSteps(id: String)
  WantCancel(id: String)
end

# A want and the token that sent it, which names the runs' owner.
struct Command
  owner: String
  want: Want
end

# Where a request goes: the health counts, a command, or an answer now.
enum Routed
  Checkup
  Asked(command: Command)
  Answered(response: Response)
end

struct Failure
  error: String
end

fn route(request: Request) : Routed
  if request.path == "/health"
    return Checkup if request.method == "GET"
    return Answered(response: not_allowed("GET"))
  end
  return collection(request) if request.path == "/runs"
  parts = request.path.split("/").drop(1)
  id = parts.get(1) or ""
  if parts.first != Some("runs") or id == "" or parts.size > 3
    return Answered(response: failed(404, "no route #{request.path}"))
  end
  case parts.get(2)
    None: only(request, "GET", WantRun(id: id))
    Some("transcript"): only(request, "GET", WantSteps(id: id))
    Some("cancel"): only(request, "POST", WantCancel(id: id))
    Some(_): Answered(response: failed(404, "no route #{request.path}"))
  end
end

fn collection(request: Request) : Routed
  return Answered(response: not_allowed("GET, POST")) if !["GET", "POST"].contains?(request.method)
  if request.method == "GET"
    return asked(request, listing(request.query))
  end
  asked(request, created(request.body))
end

fn only(request: Request, method: String, want: Want) : Routed
  return Answered(response: not_allowed(method)) if request.method != method
  asked(request, Ok(want))
end

# The command a request makes once its token is read: 401 without one, and 400 when its body or
# query is not what the route takes.
fn asked(request: Request, want: Result(Want, String)) : Routed
  case bearer(request)
    Some(owner):
      case want
        Ok(given): Asked(command: Command(owner: owner, want: given))
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

fn listing(query: Map(String, String)) : Result(Want, String)
  case query.get("state")
    Some(name):
      case status_named(name)
        Some(status): Ok(WantRuns(status: Some(status)))
        None: Error("state must be running, done, failed, over_budget, or cancelled")
      end
    None: Ok(WantRuns(status: None))
  end
end

fn created(body: String) : Result(Want, String)
  Ok(WantNew(order: try order_of(body)))
end

# An order from a POST /runs body: goal and folder given, tools and hosts lists of strings when
# given, and each budget field a whole number in its bounds, or its default when left out.
fn order_of(body: String) : Result(Order, String)
  fields = try object_of(body)
  goal = try text_field(fields, "goal")
  return Error("goal must be 1 byte to 4 KiB") if !goal?(goal)
  folder = try text_field(fields, "folder")
  if !folder?(folder)
    return Error("folder must be a path inside the service's folder of letters, digits, ., - and _, outside its runs")
  end
  tools = try texts_field(fields, "tools")
  if !tools?(tools)
    return Error("tools must each be one of list_files, read_file, search, write_file, http_get, now, named once")
  end
  hosts = try texts_field(fields, "hosts")
  return Error("hosts must be at most 32 names, each host or host:port") if !hosts?(hosts)
  Ok(order(goal, folder, tools, hosts, try budget_of(fields)))
end

fn budget_of(fields: Map(String, Json)) : Result(Budget, String)
  given = try budget_fields(fields)
  steps = try whole_in(given, "steps", 20)
  return Error("budget.steps must be from 1 to 200") if !steps?(steps)
  tokens = try whole_in(given, "tokens", 100_000)
  return Error("budget.tokens must be from 1 to 10000000") if !tokens?(tokens)
  wall_ms = try whole_in(given, "wall_ms", 60_000)
  return Error("budget.wall_ms must be from 100 to 3600000") if !wall_ms?(wall_ms)
  retries = try whole_in(given, "retries", 2)
  return Error("budget.retries must be from 0 to 10") if retries > 10
  tool_ms = try whole_in(given, "tool_ms", 5_000)
  return Error("budget.tool_ms must be from 100 to 60000") if !tool_ms?(tool_ms)
  Ok(budget(steps, tokens, wall_ms, retries.to_u32, tool_ms))
end

fn budget_fields(fields: Map(String, Json)) : Result(Map(String, Json), String)
  case fields.get("budget")
    Some(Object(given)): Ok(given)
    Some(_): Error("budget must be an object")
    None: Ok(Map.new())
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

# A list of strings, or none when the field is left out.
fn texts_field(fields: Map(String, Json), name: String) : Result(List(String), String)
  case fields.get(name)
    Some(Array(items)):
      texts = items.flat_map(fn(item) text_of(item) end)
      return Error("#{name} must be a list of strings") if texts.size != items.size
      Ok(texts)
    Some(_): Error("#{name} must be a list of strings")
    None: Ok([])
  end
end

fn text_of(item: Json) : List(String)
  case item
    String(text): [text]
    Object(_) | Array(_) | Number(_) | Bool(_) | Null: []
  end
end

# A whole number from 0 up, or `otherwise` when the field is left out.
fn whole_in(fields: Map(String, Json), name: String, otherwise: UInt64) : Result(UInt64, String)
  case fields.get(name)
    Some(value):
      whole = value.to_i64 or -1
      return Error("budget.#{name} must be a whole number") if whole < 0
      Ok(whole.to_u64)
    None: Ok(otherwise)
  end
end

# The response to an outcome of the book.
fn respond(outcome: Outcome) : Response
  ensures result.status >= 200 and result.status <= 503

  case outcome
    Made(run): json(201, shown(run))
    Found(run) | Stopped(run): json(200, shown(run))
    Listed(runs): json(200, "{\"runs\": [#{String.join(runs.map(fn(run) shown(run) end), ", ")}]}")
    Transcribed(steps): json(200, "{\"steps\": [#{String.join(steps, ", ")}]}")
    NotRunning(run): failed(409, "the run is not running: it is #{status_name(run.status)}")
    NoFolder: failed(400, "folder is not a folder inside the service's folder")
    NoRun: failed(404, "no such run")
    Unavailable(why): failed(503, why)
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

fn want_of(routed: Routed) : Option(Want)
  case routed
    Asked(command): Some(command.want)
    Checkup | Answered(_): None
  end
end

test "each route takes its methods, and any other is 405 with the ones it takes"
  assert route(Request(method: "GET", path: "/health")) == Checkup
  assert status_of(route(by("POST", "/health", ""))) == 405
  assert status_of(route(by("PUT", "/runs", ""))) == 405
  assert route(by("DELETE", "/runs/r_1", "")) is Answered(refused)
  assert refused.headers.get("allow") == Some("GET")
  assert status_of(route(by("POST", "/runs/r_1/transcript", ""))) == 405
  assert status_of(route(by("GET", "/runs/r_1/cancel", ""))) == 405
end

test "a route that does not exist is 404, whatever its method or token"
  assert status_of(route(by("GET", "/", ""))) == 404
  assert status_of(route(by("GET", "/runs/", ""))) == 404
  assert status_of(route(by("POST", "/runs/r_1/retry", ""))) == 404
  assert status_of(route(by("GET", "/runs/r_1/transcript/x", ""))) == 404
  assert status_of(route(Request(method: "GET", path: "/run"))) == 404
end

test "a missing or empty token is 401, and a token names the owner"
  assert status_of(route(Request(method: "GET", path: "/runs"))) == 401
  empty = Request(method: "GET", path: "/runs", headers: Map.new().set("authorization", "Bearer "))
  assert status_of(route(empty)) == 401
  lower = Request(method: "POST", path: "/runs/r_2/cancel",
    headers: Map.new().set("authorization", "bearer grace"))
  assert route(lower) == Asked(command: Command(owner: "grace", want: WantCancel(id: "r_2")))
end

test "each route becomes its command, and a body's budget fields left out take their defaults"
  post = by("POST", "/runs",
    "{\"goal\": \"count\", \"folder\": \"work\", \"tools\": [\"now\"], \"hosts\": [\"localhost:7951\"], \"budget\": {\"steps\": 5}}")
  wanted = Order(goal: "count", folder: "work", tools: ["now"], hosts: ["localhost:7951"],
    budget: budget(5, 100_000, 60_000, 2, 5_000))
  assert want_of(route(post)) == Some(WantNew(order: wanted))
  bare = order_of("{\"goal\": \"g\", \"folder\": \"w\"}")
  assert bare is Ok(plain)
  assert plain.tools == [] and plain.hosts == [] and plain.budget == budget(20, 100_000, 60_000, 2,
    5_000)
  assert want_of(route(by("GET", "/runs/r_1", ""))) == Some(WantRun(id: "r_1"))
  assert want_of(route(by("GET", "/runs/r_1/transcript", ""))) == Some(WantSteps(id: "r_1"))
  list = Request(method: "GET", path: "/runs", query: Map.new().set("state", "over_budget"),
    headers: Map.new().set("authorization", "Bearer ada"))
  assert want_of(route(list)) == Some(WantRuns(status: Some(OverBudget)))
  assert want_of(route(by("GET", "/runs", ""))) == Some(WantRuns(status: None))
end

test "a body that is not JSON, a missing field, or a field out of its bounds is 400 with why"
  assert route(by("POST", "/runs", "{")) is Answered(bad)
  assert bad.status == 400 and bad.body == "{\"error\": \"the body is not JSON\"}"
  assert order_of("[1]") == Error("the body must be a JSON object")
  assert order_of("{\"folder\": \"w\"}") == Error("goal is missing")
  assert order_of("{\"goal\": \"g\"}") == Error("folder is missing")
  assert order_of("{\"goal\": \"\", \"folder\": \"w\"}") is Error(_)
  assert order_of("{\"goal\": \"g\", \"folder\": \"../w\"}") is Error(_)
  assert order_of("{\"goal\": \"g\", \"folder\": \"w\", \"tools\": [\"rm\"]}") is Error(_)
  assert order_of("{\"goal\": \"g\", \"folder\": \"w\", \"tools\": \"now\"}") is Error(_)
  assert order_of("{\"goal\": \"g\", \"folder\": \"w\", \"hosts\": [\"a b\"]}") is Error(_)
  assert order_of("{\"goal\": \"g\", \"folder\": \"w\", \"budget\": 3}") is Error(_)
  assert order_of("{\"goal\": \"g\", \"folder\": \"w\", \"budget\": {\"steps\": 0}}") is Error(_)
  assert order_of("{\"goal\": \"g\", \"folder\": \"w\", \"budget\": {\"steps\": 201}}") is Error(_)
  assert order_of("{\"goal\": \"g\", \"folder\": \"w\", \"budget\": {\"tokens\": 1.5}}") is Error(_)
  assert order_of("{\"goal\": \"g\", \"folder\": \"w\", \"budget\": {\"wall_ms\": 99}}") is Error(_)
  assert order_of("{\"goal\": \"g\", \"folder\": \"w\", \"budget\": {\"retries\": 11}}") is Error(_)
  assert order_of("{\"goal\": \"g\", \"folder\": \"w\", \"budget\": {\"tool_ms\": 60001}}") is Error(_)
  assert status_of(route(Request(method: "GET", path: "/runs",
    query: Map.new().set("state", "lost"),
    headers: Map.new().set("authorization", "Bearer ada")))) == 400
end

test "each outcome is its status and its JSON"
  at = Time.fixture()
  run = record("r_1", "ada", "g", at)
  assert respond(Made(run: run)).status == 201 and respond(Made(run: run)).body == shown(run)
  assert respond(Found(run: run)).status == 200 and respond(Stopped(run: run)).status == 200
  assert respond(Listed(runs: [run, run])).body == "{\"runs\": [#{shown(run)}, #{shown(run)}]}"
  assert respond(Listed(runs: [])).body == "{\"runs\": []}"
  assert respond(Transcribed(steps: ["{\"n\": 1}"])).body == "{\"steps\": [{\"n\": 1}]}"
  assert respond(NotRunning(run: run)).status == 409
  assert respond(NoFolder).status == 400 and respond(NoRun).status == 404
  assert respond(Unavailable(why: "down")) == failed(503, "down")
  counts = Health(running: 1, done: 2, failed: 3, over_budget: 4, cancelled: 5, uptime_ms: 6)
  assert health(counts).body == "{\"running\": 1, \"done\": 2, \"failed\": 3, \"over_budget\": 4, \"cancelled\": 5, \"uptime_ms\": 6}"
end

verified: types, contracts, tests (6), property (0 seeds), sim (not run)
          proven: not run
