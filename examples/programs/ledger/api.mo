module Ledger.Api
expose Routed, route, respond, bearer, fingerprint

use Ledger.Entry{Kind, kind_named}
use Ledger.Money{Money, amount?, overdraft?, currency?, name?, reason?, key?, ttl_ms?, day?}
use Ledger.Teller{Command, Call, Answer}

intent "Read an HTTP request into a call on the journal, or answer it at once: 404 for a route that does not exist, 405 for a method the route lacks, 401 for a missing token on every route but health, 400 for a change with no idempotency-key or a key that breaks its rule, and 400 for a body or a query that is not what the route takes; and write every answer as JSON with its status."

enum Routed
  Answered(response: Response)
  Asked(call: Call)
end

fn route(request: Request) : Routed
  # body gone; regenerate
end

fn nowhere(request: Request) : Routed
  # body gone; regenerate
end

fn health(request: Request) : Routed
  # body gone; regenerate
end

# A route that reads: GET, with a token.
fn reading(request: Request, found: Bool, command: Result(Command, String)) : Routed
  # body gone; regenerate
end

# A route that changes something: POST, with a token and an idempotency-key.
fn changing(request: Request, command: Result(Command, String)) : Routed
  # body gone; regenerate
end

# What a key is compared by: the method, the path, and the body.
fn fingerprint(request: Request) : String
  # body gone; regenerate
end

# The token an authorization header carries after Bearer and a space, the scheme in any case.
fn bearer(request: Request) : Option(String)
  # body gone; regenerate
end

fn opening(body: String) : Result(Command, String)
  # body gone; regenerate
end

fn transfer(body: String) : Result(Command, String)
  # body gone; regenerate
end

fn hold(body: String) : Result(Command, String)
  # body gone; regenerate
end

fn capture(hold_id: String, body: String) : Result(Command, String)
  # body gone; regenerate
end

# A release's body may be empty; when it is an object, its reason is optional.
fn release(hold_id: String, body: String) : Result(Command, String)
  # body gone; regenerate
end

fn refund(capture_id: String, body: String) : Result(Command, String)
  # body gone; regenerate
end

fn settling(body: String) : Result(Command, String)
  # body gone; regenerate
end

# A listing's query: account and kind, each optional.
fn listing(query: Map(String, String)) : Result(Command, String)
  # body gone; regenerate
end

fn kind_of(name: String) : Result(Kind, String)
  # body gone; regenerate
end

fn object_of(body: String) : Result(Map(String, Json), String)
  # body gone; regenerate
end

fn text_field(fields: Map(String, Json), name: String) : Result(String, String)
  # body gone; regenerate
end

fn whole_field(fields: Map(String, Json), name: String) : Result(Int64, String)
  # body gone; regenerate
end

fn whole_of(value: Json, name: String) : Result(Int64, String)
  # body gone; regenerate
end

fn amount_field(fields: Map(String, Json)) : Result(Money, String)
  # body gone; regenerate
end

fn respond(answer: Answer) : Response
  # body gone; regenerate
end

fn json(status: UInt16, body: String) : Response
  # body gone; regenerate
end

fn failed(status: UInt16, error: String) : Response
  # body gone; regenerate
end

fn unauthorized() : Response
  # body gone; regenerate
end

fn not_allowed(methods: String) : Response
  # body gone; regenerate
end

fn by(method: String, path: String, body: String) : Request
  # body gone; regenerate
end

fn status_of(routed: Routed) : UInt16
  # body gone; regenerate
end

fn command_of(routed: Routed) : Option(Command)
  # body gone; regenerate
end

fn error_of(routed: Routed) : String
  # body gone; regenerate
end

test "each route takes its method, and any other is 405 with the ones it takes"
  assert status_of(route(by("POST", "/health", ""))) == 405
  assert status_of(route(by("GET", "/accounts", ""))) == 405
  assert status_of(route(by("POST", "/accounts/a_1", ""))) == 405
  assert status_of(route(by("GET", "/transfers", ""))) == 405
  assert status_of(route(by("PUT", "/holds/e_1/capture", ""))) == 405
  assert status_of(route(by("POST", "/entries", ""))) == 405
  assert route(by("DELETE", "/settle", "")) is Answered(refused)
  assert refused.headers.get("allow") == Some("POST")
end

test "a route that does not exist is 404, whatever its method or token"
  assert status_of(route(by("GET", "/", ""))) == 404
  assert status_of(route(by("GET", "/accounts/", ""))) == 404
  assert status_of(route(by("POST", "/holds/e_1/void", ""))) == 404
  assert status_of(route(by("POST", "/captures/e_1", ""))) == 404
  assert status_of(route(Request(method: "GET", path: "/account"))) == 404
end

test "a missing token is 401 on every route but health, and a change needs its idempotency-key"
  assert route(Request(method: "GET", path: "/health")) is Asked(_)
  assert status_of(route(Request(method: "GET", path: "/accounts/a_1"))) == 401
  basic = Request(method: "POST", path: "/transfers",
    headers: Map.new().set("authorization", "Basic a"))
  assert status_of(route(basic)) == 401
  keyless = Request(method: "POST", path: "/transfers",
    headers: Map.new().set("authorization", "bearer ada"), body: "{}")
  assert status_of(route(keyless)) == 400
  assert error_of(route(keyless)) == "{\"error\": \"a change needs an idempotency-key header\"}"
  var carded = by("POST", "/settle", "{\"day\": \"2026-09-14\"}")
  carded.headers = carded.headers.set("idempotency-key", "4111111111111111")
  assert status_of(route(carded)) == 400
  assert route(by("GET", "/accounts/a_1", "")) == Asked(call: Call(command: ShowAccount(id: "a_1"),
    key: "", request: ""))
end

test "each route becomes its call, with its key and the request a key is compared by"
  body = "{\"from\": \"a_1\", \"to\": \"a_2\", \"amount\": 1500}"
  assert route(by("POST", "/transfers",
    body)) == Asked(call: Call(command: MoveMoney(from: "a_1", to: "a_2", amount: 1_500), key: "k1",
    request: "POST /transfers\n#{body}"))
  opened_account = route(by("POST", "/accounts", "{\"name\": \"ada\", \"currency\": \"USD\"}"))
  assert command_of(opened_account) == Some(OpenAccount(name: "ada", currency: "USD", overdraft: 0))
  held_call = by("POST", "/holds", "{\"account\": \"a_1\", \"amount\": 5000, \"ttl_ms\": 60000}")
  assert command_of(route(held_call)) == Some(PlaceHold(account: "a_1", amount: 5_000,
    ttl_ms: 60_000))
  captured = by("POST", "/holds/e_2/capture", "{\"amount\": 4200}")
  assert command_of(route(captured)) == Some(CaptureHold(hold: "e_2", amount: 4_200))
  assert command_of(route(by("POST", "/holds/e_2/release", ""))) == Some(ReleaseHold(hold: "e_2",
    reason: "released"))
  told = by("POST", "/holds/e_2/release", "{\"reason\": \"customer asked\"}")
  assert command_of(route(told)) == Some(ReleaseHold(hold: "e_2", reason: "customer asked"))
  assert command_of(route(by("POST", "/captures/e_3/refund",
    "{\"amount\": 1}"))) == Some(RefundCapture(capture: "e_3",
    amount: 1))
  listing_request = Request(method: "GET", path: "/entries",
    query: Map.new().set("account", "a_1").set("kind", "hold"),
    headers: Map.new().set("authorization", "Bearer ada"))
  assert command_of(route(listing_request)) == Some(ListEntries(account: Some("a_1"),
    kind: Some(Hold)))
  assert command_of(route(by("POST", "/settle",
    "{\"day\": \"2026-09-14\"}"))) == Some(SettleDay(day: "2026-09-14"))
end

test "a body that is not JSON, a missing field, or a field of the wrong shape is 400 with why"
  assert error_of(route(by("POST", "/transfers", "{"))) == "{\"error\": \"the body is not JSON\"}"
  assert transfer("[1]") == Error("the body must be a JSON object")
  assert transfer("{\"to\": \"a_2\", \"amount\": 1}") == Error("from is missing")
  assert transfer("{\"from\": 1, \"to\": \"a_2\", \"amount\": 1}") == Error("from must be a string")
  assert transfer("{\"from\": \"a_1\", \"to\": \"a_2\", \"amount\": 0}") is Error(_)
  assert transfer("{\"from\": \"a_1\", \"to\": \"a_2\", \"amount\": -5}") is Error(_)
  assert transfer("{\"from\": \"a_1\", \"to\": \"a_2\", \"amount\": 1.5}") is Error(_)
  assert transfer("{\"from\": \"a_1\", \"to\": \"a_2\", \"amount\": \"15\"}") is Error(_)
  assert hold("{\"account\": \"a_1\", \"amount\": 1, \"ttl_ms\": 99}") is Error(_)
  assert hold("{\"account\": \"a_1\", \"amount\": 1}") == Error("ttl_ms is missing")
  assert opening("{\"name\": \"a b\", \"currency\": \"USD\"}") is Error(_)
  assert opening("{\"name\": \"ada\", \"currency\": \"usd\"}") is Error(_)
  assert opening("{\"name\": \"ada\", \"currency\": \"USD\", \"overdraft\": -1}") is Error(_)
  assert release("e_1", "{\"reason\": \"card 4111111111111111\"}") is Error(_)
  assert settling("{\"day\": \"2026-02-30\"}") is Error(_)
  assert listing(Map.new().set("kind", "payout")) is Error(_)
end

test "an answer is its status and its JSON"
  assert respond(Answer(status: 201, body: "{}")) == Response(status: 201,
    headers: Map.new().set("content-type", "application/json"), body: "{}")
  assert fingerprint(by("POST", "/settle", "x")) == "POST /settle\nx"
end
