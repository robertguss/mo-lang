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
  # body gone; regenerate
end

fn collection(request: Request) : Routed
  # body gone; regenerate
end

fn member(request: Request, id: String) : Routed
  # body gone; regenerate
end

# The client token an authorization header carries: Bearer, a space, and a token of 1 to 64
# letters, digits, - and _. The scheme's case does not matter.
fn bearer(request: Request) : Option(String)
  # body gone; regenerate
end

fn creating(body: String) : Command
  # body gone; regenerate
end

fn updating(id: String, body: String) : Command
  # body gone; regenerate
end

# A request body as a title and a body, or why it is not one: not JSON, not an object, a field
# missing or not a string, or a title or body that breaks its rule.
fn drafted(text: String) : Result(Draft, String)
  ensures result is Ok(draft) implies title?(draft.title) and body?(draft.body)
  # body gone; regenerate
end

fn field(fields: Map(String, Json), name: String) : Result(String, String)
  # body gone; regenerate
end

# The response to an outcome of the service.
fn respond(outcome: Outcome) : Response
  ensures result.status >= 200 and result.status <= 503
  # body gone; regenerate
end

fn health(counts: Counts) : Response
  # body gone; regenerate
end

fn json(status: UInt16, body: String) : Response
  # body gone; regenerate
end

fn failed(status: UInt16, reason: String) : Response
  # body gone; regenerate
end

fn unauthorized() : Response
  # body gone; regenerate
end

fn not_allowed(methods: String) : Response
  # body gone; regenerate
end

fn authorized(method: String, path: String, token: String, body: String) : Request
  # body gone; regenerate
end

fn asked(routed: Routed) : Option(Call)
  # body gone; regenerate
end

fn status_of(routed: Routed) : UInt16
  # body gone; regenerate
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
