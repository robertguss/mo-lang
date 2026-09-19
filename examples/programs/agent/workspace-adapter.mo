module Agent.WorkspaceAdapter
expose Settings, Scan, wire_version, file_ms, command_ms, candidate_ms, candidate_floor_ms, request_cap, response_cap, config_cap, tools, strict, scanned, members, settings, local, sent, checked, stops?, refusal?

use Agent.Tools{Call}

intent "The six workspace tools over the accepted mo-workspace-http-v1 loopback bridge: trusted settings supply the endpoint, identities, capability and timeouts, the model supplies only tool arguments; each response is checked against the contract's exact envelope, status and per-operation shapes, and anything uncertain is unknown execution that stops dispatch."

# The operator's trusted binding: the bridge's loopback port, the external run and workspace
# identities, and the private capability, which goes only into the request header.
struct Settings
  port: UInt16
  run: String
  workspace: String
  token: String
end

# A raw JSON text read byte by byte: inside a string, just after a backslash in one, inside a
# number, the colons outside strings, and whether every number is written as an integer.
struct Scan
  quoted: Bool
  escaped: Bool
  number: Bool
  colons: UInt64
  integral: Bool
end

fn wire_version() : String
  "mo-workspace-http-v1"
end

fn file_ms() : Int64
  2_000
end

fn command_ms() : Int64
  300_000
end

fn candidate_ms() : Int64
  120_000
end

fn candidate_floor_ms() : Int64
  500
end

fn request_cap() : UInt64
  851_968
end

fn response_cap() : UInt64
  524_288
end

fn config_cap() : UInt64
  4_096
end

# One byte of the scan. An escape consumes exactly one following byte, so a run of backslashes
# of either parity ends where it should.
fn scan_byte(so_far: Scan, b: UInt8) : Scan
  var next = so_far
  if so_far.quoted
    if so_far.escaped
      next.escaped = false
    else
      next.escaped = b == 92
      next.quoted = b != 34
    end
    return next
  end
  point = b == 46 or b == 101 or b == 69
  if so_far.number and point
    next.integral = false
  end
  next.number = (b >= 48 and b <= 57) or b == 45 or (so_far.number and (point or b == 43))
  next.quoted = b == 34
  if b == 58
    next.colons = so_far.colons + 1
  end
  next
end

fn scanned(text: String) : Scan
  start = Scan(quoted: false, escaped: false, number: false, colons: 0, integral: true)
  text.bytes.reduce(start, fn(scan, b) scan_byte(scan, b) end)
end

# Every object member a decoded value holds, through all arrays and objects.
fn members(value: Json) : UInt64
  case value
    Object(fields):
      fields.size + fields.values.reduce(0.to_u64, fn(n, inner)
        n + members(inner)
      end)
    Array(items): items.reduce(0.to_u64, fn(n, inner) n + members(inner) end)
    String(_) | Number(_) | Bool(_) | Null: 0
  end
end

# JSON the grammar accepts, whose integers are written as integers, and whose every key is
# distinct: a decoder that keeps the last duplicate loses at least one member, so a count of
# the colons outside strings that differs from the decoded members is a duplicate.
fn strict(text: String) : Result(Json, String)
  value = case Json.decode(text)
    Ok(found): found
    Error(_):
      return Error("grammar")
  end
  scan = scanned(text)
  return Error("number") if !scan.integral
  return Error("duplicate") if scan.colons != members(value)
  Ok(value)
end

fn exact?(fields: Map(String, Json), keys: List(String)) : Bool
  fields.size == keys.size and keys.all?(fn(key) fields.has?(key) end)
end

fn string_in(fields: Map(String, Json), key: String) : Option(String)
  case fields.get(key)
    Some(String(text)): Some(text)
    Some(_) | None: None
  end
end

fn integer_in(fields: Map(String, Json), key: String) : Option(Int64)
  case fields.get(key)
    Some(Number(value)): Number(value: value).to_i64
    Some(_) | None: None
  end
end

fn id?(text: String) : Bool
  size = text.byte_size
  size >= 1 and size <= 64 and text.bytes.all?(fn(b)
    (b >= 48 and b <= 57) or (b >= 65 and b <= 90) or (b >= 97 and b <= 122) or b == 45 or b == 95
  end)
end

fn hex?(text: String, size: UInt64) : Bool
  text.byte_size == size and text.bytes.all?(fn(b)
    (b >= 48 and b <= 57) or (b >= 97 and b <= 102)
  end)
end

# The operator's configuration, whose errors name the field and never echo its text.
fn settings(text: String) : Result(Settings, String)
  return Error("config_size") if text.byte_size > config_cap()
  fields = case strict(text)
    Ok(Object(found)): found
    Ok(_) | Error(_):
      return Error("config_json")
  end
  return Error("config_keys") if !exact?(fields,
    ["version", "port", "run_id", "workspace_id", "token"])
  return Error("config_version") if string_in(fields, "version") != Some(wire_version())
  port = integer_in(fields, "port") or 0
  return Error("config_port") if port < 1 or port > 65_535
  run = string_in(fields, "run_id") or ""
  return Error("config_run") if !id?(run)
  workspace = string_in(fields, "workspace_id") or ""
  return Error("config_workspace") if !hex?(workspace, 32)
  token = string_in(fields, "token") or ""
  return Error("config_token") if !hex?(token, 64)
  Ok(Settings(port: port.to_u16, run: run, workspace: workspace, token: token))
end

# An outcome the adapter states itself: a refusal before any request, or an uncertain result.
fn local(state: String, error: String, execution: String) : String
  "{\"adapter\": \"mo-application-workspace-v1\", \"state\": #{Json.encode(state)}, \"execution\": #{Json.encode(execution)}, \"error\": #{Json.encode(error)}}"
end

# The six operations, each routed to the bridge and never to a local tool.
fn tools() : List(String)
  ["list_files", "read_file", "search", "write_file", "exact_edit", "command"]
end

# The arguments an operation takes from the model. The command's timeout is the adapter's.
fn required(operation: String) : List(String)
  case operation
    "read_file": ["path"]
    "search": ["query"]
    "write_file": ["path", "text"]
    "exact_edit": ["path", "old_text", "new_text"]
    "command": ["command"]
    _: []
  end
end

fn optional(operation: String) : List(String)
  if operation == "list_files" or operation == "search": ["path"] else: []
end

fn fitting?(args: Map(String, String), operation: String) : Bool
  needed = required(operation)
  allowed = needed.concat(optional(operation))
  needed.all?(fn(key) args.has?(key) end) and args.keys.all?(fn(key) allowed.contains?(key) end)
end

fn opening(settings: Settings, operation: String, id: String) : String
  "{\"version\": #{Json.encode(wire_version())}, \"run_id\": #{Json.encode(settings.run)}, \"workspace_id\": #{Json.encode(settings.workspace)}, \"call_id\": #{Json.encode(id)}, \"operation\": #{Json.encode(operation)}, \"args\": "
end

# One call, sent at most once. Grant, exact arguments, identity and the encoded size are checked
# before anything is sent; the endpoint, identities, capability and timeouts are the operator's.
fn sent(http: Http, settings: Settings, call: Call, id: String, by: Deadline) : String
  return local("refusal", "grant", "not_started") if !call.granted.contains?(call.tool)
  return local("refusal", "tool", "not_started") if !tools().contains?(call.tool)
  return local("refusal", "arguments", "not_started") if !fitting?(call.args, call.tool)
  return local("refusal", "call_id", "not_started") if !id?(id)
  ms = min_of(candidate_ms(), by.remaining.ms)
  if call.tool == "command" and ms < candidate_floor_ms()
    return local("refusal", "deadline", "not_started")
  end
  head = opening(settings, call.tool, id)
  body = if call.tool == "command"
    "#{head}{\"command\": #{Json.encode(call.args.get("command") or "")}, \"timeout_ms\": #{ms}}}"
  else
    "#{head}#{Json.encode(call.args)}}"
  end
  return local("refusal", "request_too_large", "not_started") if body.byte_size > request_cap()
  posted(http, settings, call.tool, id, body, by)
end

fn posted(http: Http, settings: Settings, operation: String, id: String, body: String,
  by: Deadline) : String
  wait = by.at_most(if operation == "command": command_ms().ms else: file_ms().ms)
  return local("refusal", "deadline", "not_started") if wait.remaining == 0.ms
  headers = Map.new().set("content-type", "application/json").set("x-mo-workspace-token",
    settings.token)
  request = Request(method: "POST", path: "/tool", headers: headers, body: body)
  case http.send(request, host: "127.0.0.1", port: settings.port, within: wait)
    Ok(response): checked(response.status, response.body, settings, id, operation)
    Error(Timeout): local("timeout", "transport_timeout", "unknown")
    Error(_): local("failure", "transport", "unknown")
  end
end

# A refusal, judged from the outcome's own state field.
fn refusal?(output: String) : Bool
  case Json.decode(output)
    Ok(Object(fields)): string_in(fields, "state") == Some("refusal")
    Ok(_) | Error(_): false
  end
end

fn states() : List(String)
  ["success", "refusal", "failure", "timeout", "cancellation"]
end

fn executions() : List(String)
  ["not_started", "completed", "unknown"]
end

fn core_errors() : List(String)
  ["invalid_path",
    "invalid_utf8",
    "oversized",
    "unsupported_entry",
    "unsupported_mode",
    "empty_old",
    "multiple_matches",
    "missing_match",
    "snapshot_mode",
    "too_many_entries",
    "quota",
    "empty_search",
    "invalid_import",
    "path_conflict",
    "deadline",
    "cleanup_required",
    "quarantined",
    "closed",
    "result_too_large",
    "filesystem_refusal",
    "controller_failure",
    "request_refused",
    "transport_unknown",
    "recovery_closed",
    "duplicate_call"]
end

fn bridge_errors() : List(String)
  ["malformed",
    "unauthorized",
    "unbound",
    "not_found",
    "method",
    "unsupported_media",
    "conflict",
    "busy",
    "admission_closed",
    "call_limit",
    "journal_full",
    "response_timeout",
    "owner_unknown",
    "output_encoding",
    "invalid_result",
    "response_too_large"]
end

# A response body the contract allows for this call, verbatim; anything else is the adapter's
# unknown-execution failure, and the body never reaches the model.
fn checked(status: UInt16, body: String, settings: Settings, call: String,
  operation: String) : String
  return body if valid?(status, body, settings, call, operation)
  local("failure", "invalid_response", "unknown")
end

fn valid?(status: UInt16, body: String, settings: Settings, call: String, operation: String) : Bool
  return false if body.byte_size > response_cap()
  fields = case strict(body)
    Ok(Object(found)): found
    Ok(_) | Error(_):
      return false
  end
  keys = ["version",
    "run_id",
    "workspace_id",
    "call_id",
    "accepted",
    "state",
    "execution",
    "error",
    "result"]
  return false if !exact?(fields, keys) or string_in(fields, "version") != Some(wire_version())
  return false if !states().contains?(string_in(fields, "state") or "")
  return false if !executions().contains?(string_in(fields, "execution") or "")
  error = fields.get("error") or Null
  return false if error != Null and !core_errors().concat(bridge_errors()).contains?(string_in(fields,
    "error") or "")
  case fields.get("accepted")
    Some(Bool(value)):
      if value
        bound?(fields, settings, call) and admitted?(status, fields, operation)
      else
        refused?(status, fields, settings, call)
      end
    Some(_) | None: false
  end
end

fn bound?(fields: Map(String, Json), settings: Settings, call: String) : Bool
  string_in(fields, "run_id") == Some(settings.run) and string_in(fields,
    "workspace_id") == Some(settings.workspace) and string_in(fields, "call_id") == Some(call)
end

# A refusal before admission: nothing started, no result, and the status the contract gives its
# error. Identities are null until the whole schema and binding check, which only the admission
# refusals (409) follow, so they alone carry this call's identities.
fn refused?(status: UInt16, fields: Map(String, Json), settings: Settings, call: String) : Bool
  return false if string_in(fields, "state") != Some("refusal") or string_in(fields,
    "execution") != Some("not_started") or fields.get("result") != Some(Null)
  error = string_in(fields, "error") or ""
  return false if status != refusal_status(error)
  return bound?(fields, settings, call) if status == 409
  ["run_id", "workspace_id", "call_id"].all?(fn(key) fields.get(key) == Some(Null) end)
end

fn refusal_status(error: String) : UInt16
  case error
    "malformed": 400
    "unauthorized": 401
    "unbound": 403
    "not_found": 404
    "method": 405
    "busy" | "conflict" | "admission_closed" | "call_limit": 409
    "oversized": 413
    "unsupported_media": 415
    _: 0
  end
end

fn admitted?(status: UInt16, fields: Map(String, Json), operation: String) : Bool
  state = string_in(fields, "state") or ""
  execution = string_in(fields, "execution") or ""
  error = string_in(fields, "error")
  if status == 504
    return state == "timeout" and execution == "unknown" and error == Some("response_timeout") and fields.get("result") == Some(Null)
  end
  return false if status != 200 or error == Some("response_timeout")
  return false if state == "success" and (execution != "completed" or error is Some(_))
  case fields.get("result")
    Some(Object(result)): shaped?(operation, result, state, error)
    Some(Null): state != "success"
    Some(_) | None: false
  end
end

fn shaped?(operation: String, result: Map(String, Json), state: String,
  error: Option(String)) : Bool
  return command?(result, state, error) if operation == "command"
  key = case operation
    "list_files" | "search": "items"
    "read_file": "text"
    "write_file": "written"
    "exact_edit": "edited"
    _:
      return false
  end
  return false if !boolean?(result.get("truncated") or Null)
  return false if result.size != if result.has?(key): 2 else: 1
  return false if state == "success" and !result.has?(key)
  case result.get(key)
    Some(value): value?(operation, value)
    None: true
  end
end

fn value?(operation: String, value: Json) : Bool
  case operation
    "read_file": value is String(_)
    "write_file" | "exact_edit": boolean?(value)
    "list_files": rows?(value, ["path", "length", "sha256", "mode"])
    "search": rows?(value, ["path", "offset"])
    _: false
  end
end

fn rows?(value: Json, keys: List(String)) : Bool
  case value
    Array(items): items.all?(fn(item) row?(item, keys) end)
    Object(_) | String(_) | Number(_) | Bool(_) | Null: false
  end
end

fn row?(item: Json, keys: List(String)) : Bool
  case item
    Object(fields):
      return false if !exact?(fields, keys) or string_in(fields, "path") is None
      return false if fields.has?("sha256") and !hex?(string_in(fields, "sha256") or "", 64)
      keys.all?(fn(key)
        key == "path" or key == "sha256" or counted?(fields.get(key) or Null, 0,
          9_007_199_254_740_991)
      end)
    Array(_) | String(_) | Number(_) | Bool(_) | Null: false
  end
end

# A command's result as the accepted projection makes it: both streams strings, or both null only
# for failure/output_encoding; a success is a valid, untruncated, zero exit (a signal is not part
# of the producer's success rule, so it is not checked).
fn command?(result: Map(String, Json), state: String, error: Option(String)) : Bool
  keys = ["exit_code",
    "signal",
    "execution_valid",
    "stdout",
    "stderr",
    "encoding",
    "truncated",
    "elapsed_ms"]
  return false if !exact?(result, keys) or string_in(result, "encoding") != Some("utf-8")
  return false if !boolean?(result.get("truncated") or Null)
  valid = result.get("execution_valid") or Null
  return false if valid != Null and !boolean?(valid)
  return false if !nullable?(result.get("exit_code") or Null, -2_147_483_648, 2_147_483_647)
  return false if !nullable?(result.get("signal") or Null, 0, 255)
  return false if !nullable?(result.get("elapsed_ms") or Null, 0, 9_007_199_254_740_991)
  stdout = result.get("stdout") or Null
  stderr = result.get("stderr") or Null
  strings = stdout is String(_) and stderr is String(_)
  encoding = stdout == Null and stderr == Null and state == "failure" and error == Some("output_encoding")
  return false if !strings and !encoding
  if state == "success"
    return false if (result.get("exit_code") or Null).to_i64 != Some(0)
    return false if result.get("truncated") != Some(Bool(value: false)) or result.get("execution_valid") != Some(Bool(value: true))
  end
  (string_in(result, "stdout") or "").byte_size + (string_in(result,
    "stderr") or "").byte_size <= 65_536
end

fn boolean?(value: Json) : Bool
  value == Bool(value: true) or value == Bool(value: false)
end

fn counted?(value: Json, low: Int64, high: Int64) : Bool
  case value.to_i64
    Some(n): n >= low and n <= high
    None: false
  end
end

fn nullable?(value: Json, low: Int64, high: Int64) : Bool
  value == Null or counted?(value, low, high)
end

# Whether an outcome, once recorded, stops further dispatch. A refusal the adapter made before
# sending goes on; anything unknown, invalid, refused before admission or naming a closed or
# failing bridge stops.
fn stops?(output: String) : Bool
  fields = case Json.decode(output)
    Ok(Object(found)): found
    Ok(_) | Error(_):
      return true
  end
  execution = string_in(fields, "execution") or ""
  if fields.has?("adapter")
    return execution != "not_started"
  end
  return true if execution == "unknown" or fields.get("accepted") != Some(Bool(value: true))
  return true if stopping().contains?(string_in(fields, "error") or "")
  case fields.get("result")
    Some(Object(result)): result.get("execution_valid") == Some(Bool(value: false))
    Some(_) | None: false
  end
end

# Admitted errors that say the bridge or its owner can no longer be trusted with more work.
fn stopping() : List(String)
  ["closed",
    "recovery_closed",
    "quarantined",
    "cleanup_required",
    "journal_full",
    "admission_closed",
    "call_limit",
    "owner_unknown",
    "response_timeout",
    "transport_unknown",
    "controller_failure",
    "invalid_result",
    "duplicate_call",
    "request_refused"]
end

fn configured() : Settings
  Settings(port: 1, run: "r", workspace: "0123456789abcdef0123456789abcdef", token: "ab".repeat(32))
end

test "strict JSON counts members through arrays and objects, and escapes of either parity"
  assert strict("{\"s\":\"\\\\\",\"a\":1}") is Ok(_)
  assert strict("{\"a\":1,\"a\":2}") == Error("duplicate")
  assert strict("{\"a\":1,\"\\u0061\":2}") == Error("duplicate")
  assert strict("{\"x\":[{\"b\":1,\"b\":{\"c\":1}}]}") == Error("duplicate")
  assert strict("{\"q\":\"a:b\\\":c\",\"n\":-12}") is Ok(_)
  assert strict("{\"n\":1.0}") == Error("number") and strict("{\"n\":1e0}") == Error("number")
  assert strict("{\"t\":true,\"f\":false,\"e\":\"1.5e3\"}") is Ok(_)
  assert strict("{\"n\":-9007199254740993,\"m\":-9007199254740991}") is Ok(Object(edge))
  assert integer_in(edge, "n") is None and integer_in(edge, "m") == Some(-9_007_199_254_740_991)
  assert strict("{\"a\":NaN}") == Error("grammar") and strict("{\"a\":\"\\ud800\"}") == Error("grammar")
end

test "the operator's configuration is exact, and its errors never echo it"
  token = "ab".repeat(32)
  good = "{\"version\":\"mo-workspace-http-v1\",\"port\":7000,\"run_id\":\"r_1\",\"workspace_id\":\"0123456789abcdef0123456789abcdef\",\"token\":\"#{token}\"}"
  assert settings(good) == Ok(Settings(port: 7_000, run: "r_1",
    workspace: "0123456789abcdef0123456789abcdef", token: token))
  assert settings(good.replace("7000", "0")) == Error("config_port")
  assert settings(good.replace("7000", "7000.0")) == Error("config_json")
  assert settings(good.replace("\"r_1\"", "\"r 1\"")) == Error("config_run")
  assert settings(good.replace(token, "AB".repeat(32))) == Error("config_token")
  assert settings(good.replace("}", ",\"port\":1}")) == Error("config_json")
  assert settings(good.replace("}", ",\"x\":1}")) == Error("config_keys")
  assert settings(" ".repeat(4_097)) == Error("config_size")
  assert settings(good.replace("7000", "7000")) is Ok(_)
end

test "a valid admitted outcome is kept verbatim, and a mismatched identity is unknown"
  settings = configured()
  body = "{\"version\":\"mo-workspace-http-v1\",\"run_id\":\"r\",\"workspace_id\":\"0123456789abcdef0123456789abcdef\",\"call_id\":\"1\",\"accepted\":true,\"state\":\"success\",\"execution\":\"completed\",\"error\":null,\"result\":{\"text\":\"hi\",\"truncated\":false}}"
  assert checked(200, body, settings, "1", "read_file") == body
  assert !stops?(body)
  bad = local("failure", "invalid_response", "unknown")
  assert checked(200, body, settings, "2", "read_file") == bad and stops?(bad)
  assert checked(200, body, settings, "1", "write_file") == bad
  assert checked(500, body, settings, "1", "read_file") == bad
  assert !stops?(local("refusal", "grant", "not_started"))
end
