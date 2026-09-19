module WorkspaceServer.Schema
expose Call, call, version, operations, raw_keys, decoded_keys

use WorkspaceServer.Wire{Refusal, malformed}

intent "Read one request body as the contract fixes it: strict JSON with no repeated key at any depth, exactly the six top-level keys, the version string, run and call IDs of 1 to 64 ASCII letters, digits, _ and -, a 32 lowercase hex workspace ID, the run and workspace this server was given, and an operation with exactly its arguments, each a string but an integer timeout_ms of 500 to 120,000."

struct Call
  run_id: String
  workspace_id: String
  call_id: String
  operation: String
  args: Map(String, String)
  timeout_ms: UInt64
end

fn version() : String
  "mo-workspace-http-v1"
end

fn operations() : List(String)
  ["list_files", "read_file", "search", "write_file", "exact_edit", "command"]
end

fn required(operation: String) : List(String)
  case operation
    "read_file": ["path"]
    "search": ["query"]
    "write_file": ["path", "text"]
    "exact_edit": ["path", "old_text", "new_text"]
    "command": ["command", "timeout_ms"]
    _: []
  end
end

fn optional(operation: String) : List(String)
  if operation == "list_files" or operation == "search": ["path"] else: []
end

# The call a body spells for this run and workspace, or its refusal: 400, or 403 for a
# well-formed call bound to another run or workspace.
fn call(body: String, run_id: String, workspace_id: String) : Result(Call, Refusal)
  fields = try object_of(body)
  keys = ["version", "run_id", "workspace_id", "call_id", "operation", "args"]
  return Error(malformed()) if fields.size != 6 or !keys.all?(fn(k) fields.has?(k) end)
  return Error(malformed()) if text_of(fields.get("version")) != Some(version())
  run = try id(fields.get("run_id"), false)
  workspace = try id(fields.get("workspace_id"), true)
  call_id = try id(fields.get("call_id"), false)
  return Error(Refusal(status: 403, error: "unbound")) if run != run_id or workspace != workspace_id
  operation = text_of(fields.get("operation")) or ""
  return Error(malformed()) if !operations().contains?(operation)
  given = try args_of(fields.get("args"))
  names = given.keys
  wanted = required(operation)
  return Error(malformed()) if !wanted.all?(fn(k) names.contains?(k) end)
  allowed = wanted.concat(optional(operation))
  return Error(malformed()) if !names.all?(fn(k) allowed.contains?(k) end)
  timeout = try timeout_of(given.get("timeout_ms"))
  args = try strings_of(given.remove("timeout_ms"))
  Ok(Call(run_id: run, workspace_id: workspace, call_id: call_id, operation: operation, args: args,
    timeout_ms: timeout))
end

# The top-level object, when the body is JSON with no key repeated in any object.
fn object_of(body: String) : Result(Map(String, Json), Refusal)
  case Json.decode(body)
    Ok(value):
      fields = try (fields_of(value).map(fn(f) Ok(f) end) or Error(malformed()))
      return Error(malformed()) if raw_keys(body) != decoded_keys(value)
      Ok(fields)
    Error(_): Error(malformed())
  end
end

fn args_of(value: Option(Json)) : Result(Map(String, Json), Refusal)
  case value
    Some(v): fields_of(v).map(fn(f) Ok(f) end) or Error(malformed())
    None: Error(malformed())
  end
end

fn text_of(value: Option(Json)) : Option(String)
  case value
    Some(v): string_of(v)
    None: None
  end
end

fn fields_of(value: Json) : Option(Map(String, Json))
  case value
    Object(fields): Some(fields)
    Array(_) | String(_) | Number(_) | Bool(_) | Null: None
  end
end

fn string_of(value: Json) : Option(String)
  case value
    String(text): Some(text)
    Object(_) | Array(_) | Number(_) | Bool(_) | Null: None
  end
end

fn id(value: Option(Json), workspace: Bool) : Result(String, Refusal)
  text = text_of(value) or ""
  bytes = text.bytes
  if workspace
    return Error(malformed()) if bytes.size != 32 or !bytes.all?(fn(b)
      (b >= 48 and b <= 57) or (b >= 97 and b <= 102)
    end)
    return Ok(text)
  end
  return Error(malformed()) if bytes.size == 0 or bytes.size > 64 or !bytes.all?(fn(b)
    id_byte?(b)
  end)
  Ok(text)
end

fn id_byte?(b: UInt8) : Bool
  (b >= 48 and b <= 57) or (b >= 65 and b <= 90) or (b >= 97 and b <= 122) or b == 95 or b == 45
end

# 0 when the call has no timeout_ms.
fn timeout_of(value: Option(Json)) : Result(UInt64, Refusal)
  case value
    None: Ok(0)
    Some(v):
      whole = v.to_i64 or 0
      return Error(malformed()) if whole < 500 or whole > 120_000 or Json.encode(v) != "#{whole}.0"
      Ok(whole.to_u64)
  end
end

fn strings_of(fields: Map(String, Json)) : Result(Map(String, String), Refusal)
  var args = Map.new()
  for entry in fields.entries
    text = try (string_of(entry.1).map(fn(t) Ok(t) end) or Error(malformed()))
    args = args.set(entry.0, text)
  end
  Ok(args)
end

# How many object keys the text holds, repeats counted: a string whose closing quote is
# followed by a colon is a key. A quote after an odd run of backslashes is inside its string.
fn raw_keys(body: String) : UInt64
  pieces = body.split("\"")
  var inside = false
  var keys = 0
  for i in 1..pieces.size
    piece = pieces.get(i) or ""
    escaped = inside and odd_backslashes?(pieces.get(i - 1) or "")
    if !escaped
      inside = !inside
      if !inside and piece.trim.starts_with?(":")
        keys += 1
      end
    end
  end
  keys
end

fn odd_backslashes?(piece: String) : Bool
  var run = 0
  for b in piece.bytes.reverse
    if b != 92
      break
    end
    run += 1
  end
  run % 2 == 1
end

# How many keys the decoded value holds, which a repeated key has lost.
fn decoded_keys(value: Json) : UInt64
  case value
    Object(fields): fields.size + fields.values.map(fn(v) decoded_keys(v) end).sum
    Array(items): items.map(fn(v) decoded_keys(v) end).sum
    String(_) | Number(_) | Bool(_) | Null: 0
  end
end

fn body(args: String) : String
  "{\"version\":\"mo-workspace-http-v1\",\"run_id\":\"run-1\",\"workspace_id\":\"0123456789abcdef0123456789abcdef\",\"call_id\":\"c1\",\"operation\":\"read_file\",\"args\":#{args}}"
end

fn ws() : String
  "0123456789abcdef0123456789abcdef"
end

test "a whole call reads back"
  got = call(body("{\"path\":\"a\"}"), "run-1", ws())
  assert got == Ok(Call(run_id: "run-1", workspace_id: ws(), call_id: "c1", operation: "read_file",
    args: Map.new().set("path", "a"), timeout_ms: 0))
end

test "repeated keys, at the top or deeper, are malformed"
  assert call("{\"x\":1,\"x\":2}", "run-1", ws()) == Error(malformed())
  assert call(body("{\"path\":\"a\",\"path\":\"b\"}"), "run-1", ws()) == Error(malformed())
  assert raw_keys("{\"a\\\"\":1,\"b\":\"x\\\\\",\"c\":[\"d\",{\"e\":2}]}") == 4
  assert raw_keys("{\"k\" : \"v:\"}") == 1
end

test "not JSON, not an object, nonfinite, a lone surrogate: malformed"
  bad = ["{\"x\":NaN}", "{\"x\":\"\\ud800\"}", "[]", "", "{\"x\":1e999}"]
  assert bad.all?(fn(text) call(text, "run-1", ws()) == Error(malformed()) end)
end

test "types, extras and IDs"
  assert call(body("{\"path\":true}"), "run-1", ws()) == Error(malformed())
  assert call(body("{\"path\":0}"), "run-1", ws()) == Error(malformed())
  assert call(body("{\"path\":null}"), "run-1", ws()) == Error(malformed())
  assert call(body("{\"path\":[]}"), "run-1", ws()) == Error(malformed())
  assert call(body("{\"path\":\"a\",\"extra\":\"x\"}"), "run-1", ws()) == Error(malformed())
  assert call(body("{}"), "run-1", ws()) == Error(malformed())
  extra = body("{\"path\":\"a\"}").replace("\"args\"", "\"extra\":1,\"args\"")
  assert call(extra, "run-1", ws()) == Error(malformed())
  bad_id = body("{\"path\":\"a\"}").replace("\"c1\"", "\"c 1\"")
  assert call(bad_id, "run-1", ws()) == Error(malformed())
end

test "another run or workspace is unbound, after the shape is whole"
  assert call(body("{\"path\":\"a\"}"), "run-2",
    ws()) == Error(Refusal(status: 403, error: "unbound"))
  other = body("{\"path\":\"a\"}").replace(ws(), "f".repeat(32))
  assert call(other, "run-1", ws()) == Error(Refusal(status: 403, error: "unbound"))
end

test "a command's timeout is an integer of 500 to 120,000"
  pairs = [("500", true),
    ("120000", true),
    ("499", false),
    ("120001", false),
    ("true", false),
    ("\"900\"", false),
    ("900.5", false)]
  command = body("{\"command\":\"x\",\"timeout_ms\":T}").replace("\"read_file\"", "\"command\"")
  assert pairs.all?(fn(p)
    (call(command.replace("T", p.0), "run-1", ws()) != Error(malformed())) == p.1
  end)
end

verified: types, contracts, tests (6), property (0 seeds), sim (not run)
          proven: not run
