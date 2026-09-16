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
  parts = request.path.split("/").drop(1)
  head = parts.first or ""
  named = parts.get(1) or ""
  verb = parts.get(2) or ""
  return health(request) if request.path == "/health"
  if request.path == "/accounts"
    return Answered(response: not_allowed("POST")) if request.method != "POST"
    return changing(request, opening(request.body))
  end
  if parts.size == 2 and head == "accounts" and named != ""
    return reading(request, request.method == "GET", Ok(ShowAccount(id: named)))
  end
  if request.path == "/transfers"
    return Answered(response: not_allowed("POST")) if request.method != "POST"
    return changing(request, transfer(request.body))
  end
  if request.path == "/holds"
    return Answered(response: not_allowed("POST")) if request.method != "POST"
    return changing(request, hold(request.body))
  end
  if parts.size == 3 and head == "holds" and named != "" and verb == "capture"
    return Answered(response: not_allowed("POST")) if request.method != "POST"
    return changing(request, capture(named, request.body))
  end
  if parts.size == 3 and head == "holds" and named != "" and verb == "release"
    return Answered(response: not_allowed("POST")) if request.method != "POST"
    return changing(request, release(named, request.body))
  end
  if parts.size == 3 and head == "captures" and named != "" and verb == "refund"
    return Answered(response: not_allowed("POST")) if request.method != "POST"
    return changing(request, refund(named, request.body))
  end
  if request.path == "/entries"
    return reading(request, request.method == "GET", listing(request.query))
  end
  if request.path == "/settle"
    return Answered(response: not_allowed("POST")) if request.method != "POST"
    return changing(request, settling(request.body))
  end
  nowhere(request)
end

fn nowhere(request: Request) : Routed
  Answered(response: failed(404, "no route #{request.path}"))
end

fn health(request: Request) : Routed
  return Answered(response: not_allowed("GET")) if request.method != "GET"
  Asked(call: Call(command: CheckHealth, key: "", request: ""))
end

# A route that reads: GET, with a token.
fn reading(request: Request, found: Bool, command: Result(Command, String)) : Routed
  return Answered(response: not_allowed("GET")) if !found
  case bearer(request)
    None: Answered(response: unauthorized())
    Some(_):
      case command
        Ok(wanted): Asked(call: Call(command: wanted, key: "", request: ""))
        Error(why): Answered(response: failed(400, why))
      end
  end
end

# A route that changes something: POST, with a token and an idempotency-key.
fn changing(request: Request, command: Result(Command, String)) : Routed
  return Answered(response: unauthorized()) if bearer(request) is None
  given = request.headers.get("idempotency-key") or ""
  if given == ""
    return Answered(response: failed(400, "a change needs an idempotency-key header"))
  end
  if !key?(given)
    return Answered(response: failed(400,
      "idempotency-key must be 1 to 128 bytes of plain text with no run of 16 digits"))
  end
  case command
    Ok(wanted): Asked(call: Call(command: wanted, key: given, request: fingerprint(request)))
    Error(why): Answered(response: failed(400, why))
  end
end

# What a key is compared by: the method, the path, and the body.
fn fingerprint(request: Request) : String
  "#{request.method} #{request.path}\n#{request.body}"
end

# The token an authorization header carries after Bearer and a space, the scheme in any case.
fn bearer(request: Request) : Option(String)
  header = try request.headers.get("authorization")
  return None if header.slice(0, 7).to_lower != "bearer "
  token = header.slice(7, header.size).trim
  return None if token == ""
  Some(token)
end

fn opening(body: String) : Result(Command, String)
  fields = try object_of(body)
  named = try text_field(fields, "name")
  if !name?(named)
    return Error("name must be 1 to 64 letters, digits, - and _, with no run of 16 digits")
  end
  held = try text_field(fields, "currency")
  return Error("currency must be three uppercase letters") if !currency?(held)
  drawn = try (if fields.has?("overdraft"): whole_field(fields, "overdraft") else: Ok(0))
  if !overdraft?(drawn)
    return Error("overdraft must be a whole number from 0 to 1000000000000")
  end
  Ok(OpenAccount(name: named, currency: held, overdraft: drawn))
end

fn transfer(body: String) : Result(Command, String)
  fields = try object_of(body)
  from = try text_field(fields, "from")
  to = try text_field(fields, "to")
  amount = try amount_field(fields)
  Ok(MoveMoney(from: from, to: to, amount: amount))
end

fn hold(body: String) : Result(Command, String)
  fields = try object_of(body)
  account = try text_field(fields, "account")
  amount = try amount_field(fields)
  ttl = try whole_field(fields, "ttl_ms")
  return Error("ttl_ms must be a whole number from 100 to 86400000") if !ttl_ms?(ttl)
  Ok(PlaceHold(account: account, amount: amount, ttl_ms: ttl))
end

fn capture(hold_id: String, body: String) : Result(Command, String)
  fields = try object_of(body)
  amount = try amount_field(fields)
  Ok(CaptureHold(hold: hold_id, amount: amount))
end

# A release's body may be empty; when it is an object, its reason is optional.
fn release(hold_id: String, body: String) : Result(Command, String)
  return Ok(ReleaseHold(hold: hold_id, reason: "released")) if body.trim == ""
  fields = try object_of(body)
  return Ok(ReleaseHold(hold: hold_id, reason: "released")) if !fields.has?("reason")
  why = try text_field(fields, "reason")
  if !reason?(why)
    return Error("reason must be 1 to 256 bytes of plain text with no run of 16 digits")
  end
  Ok(ReleaseHold(hold: hold_id, reason: why))
end

fn refund(capture_id: String, body: String) : Result(Command, String)
  fields = try object_of(body)
  amount = try amount_field(fields)
  Ok(RefundCapture(capture: capture_id, amount: amount))
end

fn settling(body: String) : Result(Command, String)
  fields = try object_of(body)
  day = try text_field(fields, "day")
  return Error("day must be a date written YYYY-MM-DD") if !day?(day)
  Ok(SettleDay(day: day))
end

# A listing's query: account and kind, each optional.
fn listing(query: Map(String, String)) : Result(Command, String)
  named = query.get("account")
  wanted = case query.get("kind")
    Some(text): Some(try kind_of(text))
    None: None
  end
  Ok(ListEntries(account: named, kind: wanted))
end

fn kind_of(name: String) : Result(Kind, String)
  case kind_named(name)
    Some(kind): Ok(kind)
    None: Error("kind must be transfer, hold, capture, release, refund, or settlement")
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

fn whole_field(fields: Map(String, Json), name: String) : Result(Int64, String)
  return Error("#{name} is missing") if !fields.has?(name)
  whole_of(fields.get(name) or Null, name)
end

fn whole_of(value: Json, name: String) : Result(Int64, String)
  case value.to_i64
    Some(n): Ok(n)
    None: Error("#{name} must be a whole number")
  end
end

fn amount_field(fields: Map(String, Json)) : Result(Money, String)
  n = try whole_field(fields, "amount")
  return Error("amount must be a whole number from 1 to 1000000000000") if !amount?(n)
  Ok(n)
end

fn respond(answer: Answer) : Response
  json(answer.status, answer.body)
end

fn json(status: UInt16, body: String) : Response
  Response(status: status, headers: Map.new().set("content-type", "application/json"), body: body)
end

fn failed(status: UInt16, error: String) : Response
  json(status, "{\"error\": #{Json.encode(error)}}")
end

fn unauthorized() : Response
  failed(401, "a request needs authorization: Bearer <token>")
end

fn not_allowed(methods: String) : Response
  var response = failed(405, "this route takes #{methods}")
  response.headers = response.headers.set("allow", methods)
  response
end

fn by(method: String, path: String, body: String) : Request
  Request(method: method, path: path,
    headers: Map.new().set("authorization", "Bearer ada").set("idempotency-key", "k1"), body: body)
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

fn error_of(routed: Routed) : String
  case routed
    Answered(response): response.body
    Asked(_): ""
  end
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

verified: types, contracts, tests (6), property (0 seeds), sim (not run)
          proven: not run
