module Notes.Api
expose Routed, Draft, Failure, Waiting, Page, route, respond, health, bearer, drafted

use Notes.Limits{token?}
use Notes.Note{Note, Command, Call, Outcome, Counts, title?, body?}

intent "Read an HTTP request into a call on the notes service, or answer it at once with 404 for a route that does not exist, 405 for a method the route does not have, and 401 for a missing or malformed token; and write every outcome as JSON with its status."

# Where a request goes: the health counts, a call on the service, or an answer now.
enum Routed
  Checkup
  Asked(call: Call)
  Answered(response: Response)
end

# The JSON a create or an update carries.
struct Draft
  title: String
  body: String
end

struct Failure
  error: String
end

struct Waiting
  error: String
  retry_after_ms: Int64
end

struct Page
  notes: List(Note)
end

fn route(request: Request) : Routed
  path = request.path
  if path == "/health"
    return Checkup if request.method == "GET"
    return Answered(response: not_allowed("GET"))
  end
  if path == "/notes"
    return collection(request)
  end
  id = path.slice(7, path.size)
  if path.starts_with?("/notes/") and id != "" and !id.contains?("/")
    return member(request, id)
  end
  Answered(response: failed(404, "no route #{path}"))
end

fn collection(request: Request) : Routed
  return Answered(response: not_allowed("GET, POST")) if !["GET", "POST"].contains?(request.method)
  case bearer(request)
    Some(owner):
      if request.method == "GET"
        prefix = request.query.get("prefix") or ""
        return Asked(call: Call(owner: owner, command: Listing(prefix: prefix)))
      end
      Asked(call: Call(owner: owner, command: creating(request.body)))
    None: Answered(response: unauthorized())
  end
end

fn member(request: Request, id: String) : Routed
  allowed = ["GET", "PUT", "DELETE"]
  return Answered(response: not_allowed("GET, PUT, DELETE")) if !allowed.contains?(request.method)
  case bearer(request)
    Some(owner):
      command = case request.method
        "GET": Fetch(id: id)
        "DELETE": Remove(id: id)
        _: updating(id, request.body)
      end
      Asked(call: Call(owner: owner, command: command))
    None: Answered(response: unauthorized())
  end
end

# The client token an authorization header carries: Bearer, a space, and a token of 1 to 64
# letters, digits, - and _. The scheme's case does not matter.
fn bearer(request: Request) : Option(String)
  header = try request.headers.get("authorization")
  return None if header.slice(0, 7).to_lower != "bearer "
  token = header.slice(7, header.size)
  return None if !token?(token)
  Some(token)
end

fn creating(body: String) : Command
  case drafted(body)
    Ok(draft): Create(title: draft.title, body: draft.body)
    Error(reason): Refuse(reason: reason)
  end
end

fn updating(id: String, body: String) : Command
  case drafted(body)
    Ok(draft): Update(id: id, title: draft.title, body: draft.body)
    Error(reason): Refuse(reason: reason)
  end
end

# A request body as a title and a body, or why it is not one: not JSON, not an object, a field
# missing or not a string, or a title or body that breaks its rule.
fn drafted(text: String) : Result(Draft, String)
  ensures result is Ok(draft) implies title?(draft.title) and body?(draft.body)

  case Json.decode(text)
    Ok(Object(fields)):
      title = try field(fields, "title")
      body = try field(fields, "body")
      return Error("title must be 1 to 200 bytes with no control characters") if !title?(title)
      if !body?(body)
        return Error("body must be at most 60 KiB with no control characters but newlines")
      end
      Ok(Draft(title: title, body: body))
    Ok(_): Error("the body must be a JSON object")
    Error(_): Error("the body is not JSON")
  end
end

fn field(fields: Map(String, Json), name: String) : Result(String, String)
  case fields.get(name)
    Some(String(text)): Ok(text)
    Some(_): Error("#{name} must be a string")
    None: Error("#{name} is missing")
  end
end

# The response to an outcome of the service.
fn respond(outcome: Outcome) : Response
  ensures result.status >= 200 and result.status <= 503

  case outcome
    Made(note): json(201, Json.encode(note))
    Found(note): json(200, Json.encode(note))
    Listed(notes): json(200, Json.encode(Page(notes: notes)))
    Removed: Response(status: 204, body: "")
    Missing: failed(404, "no such note")
    Refused(reason): failed(400, reason)
    Limited(wait): json(429, Json.encode(Waiting(error: "rate limited", retry_after_ms: wait)))
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

fn unauthorized() : Response
  failed(401, "a request needs authorization: Bearer <token>")
end

fn not_allowed(methods: String) : Response
  var response = failed(405, "this route takes #{methods}")
  response.headers = response.headers.set("allow", methods)
  response
end

fn authorized(method: String, path: String, token: String, body: String) : Request
  headers = Map.new().set("authorization", "Bearer #{token}")
  Request(method: method, path: path, headers: headers, body: body)
end

fn asked(routed: Routed) : Option(Call)
  case routed
    Asked(call): Some(call)
    Checkup: None
    Answered(_): None
  end
end

fn status_of(routed: Routed) : UInt16
  case routed
    Answered(response): response.status
    Checkup: 200
    Asked(_): 0
  end
end

test "each route takes its methods, and any other method is 405 with the ones it takes"
  assert route(Request(method: "GET", path: "/health")) == Checkup
  assert status_of(route(Request(method: "POST", path: "/health"))) == 405
  assert status_of(route(authorized("PATCH", "/notes", "ada", ""))) == 405
  put_all = route(authorized("PUT", "/notes", "ada", ""))
  assert put_all is Answered(refused)
  assert refused.headers.get("allow") == Some("GET, POST")
  assert status_of(route(authorized("POST", "/notes/n_1", "ada", ""))) == 405
end

test "a route that does not exist is 404, whatever its method or token"
  assert status_of(route(authorized("GET", "/", "ada", ""))) == 404
  assert status_of(route(authorized("GET", "/notes/", "ada", ""))) == 404
  assert status_of(route(authorized("GET", "/notes/n_1/x", "ada", ""))) == 404
  assert status_of(route(Request(method: "GET", path: "/note"))) == 404
end

test "a missing, empty, or malformed token is 401, and a good one names the client"
  assert status_of(route(Request(method: "GET", path: "/notes"))) == 401
  assert status_of(route(authorized("GET", "/notes", "", ""))) == 401
  assert status_of(route(authorized("GET", "/notes", "a.b", ""))) == 401
  assert status_of(route(authorized("GET", "/notes", "k".repeat(65), ""))) == 401
  basic = Request(method: "GET", path: "/notes",
    headers: Map.new().set("authorization", "Basic ada"))
  assert status_of(route(basic)) == 401
  lower = Request(method: "GET", path: "/notes",
    headers: Map.new().set("authorization", "bearer ada"))
  assert asked(route(lower)) == Some(Call(owner: "ada", command: Listing(prefix: "")))
end

test "each route becomes its call"
  listing = Request(method: "GET", path: "/notes", query: Map.new().set("prefix", "to do"),
    headers: Map.new().set("authorization", "Bearer ada"))
  assert asked(route(listing)) == Some(Call(owner: "ada", command: Listing(prefix: "to do")))
  post = authorized("POST", "/notes", "ada", "{\"title\": \"t\", \"body\": \"b\"}")
  assert asked(route(post)) == Some(Call(owner: "ada", command: Create(title: "t", body: "b")))
  put = authorized("PUT", "/notes/n_3", "ada", "{\"body\": \"\", \"title\": \"u\", \"extra\": 1}")
  assert asked(route(put)) == Some(Call(owner: "ada",
    command: Update(id: "n_3", title: "u", body: "")))
  assert asked(route(authorized("GET", "/notes/n_3", "ada", ""))) == Some(Call(owner: "ada",
    command: Fetch(id: "n_3")))
  assert asked(route(authorized("DELETE", "/notes/n_3", "ada", ""))) == Some(Call(owner: "ada",
    command: Remove(id: "n_3")))
end

test "a body that is not JSON, not an object, missing a field, or of the wrong shape is refused with why"
  assert drafted("{\"title\": \"t\"") == Error("the body is not JSON")
  assert drafted("[\"t\", \"b\"]") == Error("the body must be a JSON object")
  assert drafted("{\"body\": \"b\"}") == Error("title is missing")
  assert drafted("{\"title\": \"t\", \"body\": 3}") == Error("body must be a string")
  assert drafted("{\"title\": \"\", \"body\": \"\"}") is Error(_)
  assert drafted("{\"title\": \"a\\u0000b\", \"body\": \"\"}") is Error(_)
  assert drafted("{\"title\": \"t\", \"body\": \"line\\nline\"}") == Ok(Draft(title: "t",
    body: "line\nline"))
  post = authorized("POST", "/notes", "ada", "")
  assert asked(route(post)) == Some(Call(owner: "ada",
    command: Refuse(reason: "the body is not JSON")))
end

test "each outcome is its status and its JSON"
  at = Time.fixture()
  kept = Note(id: "n_1", title: "t", body: "b", created_at: at, updated_at: at)
  text = "{\"id\": \"n_1\", \"title\": \"t\", \"body\": \"b\", \"created_at\": \"2026-01-01T00:00:00Z\", \"updated_at\": \"2026-01-01T00:00:00Z\"}"
  assert respond(Made(note: kept)).status == 201
  assert respond(Made(note: kept)).body == text
  assert respond(Found(note: kept)) == json(200, text)
  assert respond(Listed(notes: [kept])).body == "{\"notes\": [#{text}]}"
  assert respond(Listed(notes: [])).body == "{\"notes\": []}"
  assert respond(Removed) == Response(status: 204, body: "")
  assert respond(Missing) == json(404, "{\"error\": \"no such note\"}")
  assert respond(Refused(reason: "title is missing")).status == 400
  assert respond(Limited(retry_after_ms: 1_500)).body == "{\"error\": \"rate limited\", \"retry_after_ms\": 1500}"
  assert respond(Unavailable(reason: "the log did not take the change")).status == 503
  assert health(Counts(notes: 2, clients: 1,
    uptime_ms: 40)).body == "{\"notes\": 2, \"clients\": 1, \"uptime_ms\": 40}"
end

property "any valid title and body sent as JSON become a create of that title and body"
  for title in any(String), body in any(String) if title?(title) and body?(body)
    post = authorized("POST", "/notes", "ada", Json.encode(Draft(title: title, body: body)))
    assert asked(route(post)) == Some(Call(owner: "ada", command: Create(title: title, body: body)))
  end
end

verified: types, contracts, tests (7), property (200 seeds), sim (not run)
          proven: not run
