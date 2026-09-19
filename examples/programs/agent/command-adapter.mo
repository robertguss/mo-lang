module Agent.CommandAdapter
expose Endpoint, dispatched, terminal?, refused?, failure

intent "Send one inert fixture key to an operator-fixed loopback command endpoint; validate identities, types and bounded output, and never retry uncertain execution."

struct Endpoint
  host: String
  port: UInt16
  workspace: String
end

fn failure(state: String, error: String, execution: String) : String
  "{\"state\": #{Json.encode(state)}, \"error_code\": #{Json.encode(error)}, \"execution\": #{Json.encode(execution)}}"
end

fn dispatched(http: Http, endpoint: Endpoint, run: String, call: String, command: String,
  by: Deadline) : String
  return failure("timeout", "deadline", "not_started") if by.remaining == 0.ms
  ms = by.remaining.ms
  body = "{\"version\": 1, \"run_id\": #{Json.encode(run)}, \"call_id\": #{Json.encode(call)}, \"workspace_id\": #{Json.encode(endpoint.workspace)}, \"command\": #{Json.encode(command)}, \"timeout_ms\": #{ms}, \"max_output_bytes\": 65536}"
  request = Request(method: "POST", path: "/fixture/v1/command",
    headers: Map.new().set("content-type", "application/json"), body: body)
  case http.send(request, host: endpoint.host, port: endpoint.port, within: by)
    # A response in hand is what the endpoint did, reported as it said even when the deadline
    # has just passed; the run's own budget decides whether it goes on.
    Ok(response):
      return failure("failure", "http_status", "unknown") if response.status != 200
      checked(response.body, run, call, endpoint.workspace)
    Error(Timeout): failure("timeout", "transport", "unknown")
    Error(_): failure("failure", "transport", "unknown")
  end
end

fn text(fields: Map(String, Json), key: String) : Option(String)
  case fields.get(key)
    Some(String(value)): Some(value)
    Some(_) | None: None
  end
end

fn nullable_integer?(value: Json, nonnegative: Bool) : Bool
  return true if value == Null
  case value
    Number(_):
      case value.to_i64
        Some(n): !nonnegative or n >= 0
        None: false
      end
    Object(_) | Array(_) | String(_) | Bool(_) | Null: false
  end
end

fn checked(body: String, run: String, call: String, workspace: String) : String
  bad = failure("failure", "invalid_response", "unknown")
  return bad if body.byte_size > 400_000
  fields = case Json.decode(body)
    Ok(Object(found)): found
    Ok(_) | Error(_):
      return bad
  end
  required = ["version",
    "run_id",
    "call_id",
    "workspace_id",
    "state",
    "exit_code",
    "stdout",
    "stderr",
    "stdout_truncated",
    "stderr_truncated",
    "elapsed_ms",
    "error_code",
    "execution"]
  return bad if !required.all?(fn(key) fields.has?(key) end)
  return bad if fields.get("version") != Some(Number(value: 1.0))
  return bad if text(fields, "run_id") != Some(run) or text(fields,
    "call_id") != Some(call) or text(fields, "workspace_id") != Some(workspace)
  state = text(fields, "state") or ""
  execution = text(fields, "execution") or ""
  return bad if !["success", "refusal", "failure", "timeout", "cancellation"].contains?(state)
  return bad if !["completed", "not_started", "unknown"].contains?(execution)
  return bad if !["none",
    "refused",
    "command_failed",
    "timeout",
    "cancelled",
    "internal"].contains?(text(fields, "error_code") or "")
  return bad if text(fields, "stdout") is None or text(fields, "stderr") is None
  return bad if (text(fields, "stdout") or "").byte_size + (text(fields,
    "stderr") or "").byte_size > 65_536
  return bad if !boolean?(fields.get("stdout_truncated") or Null) or !boolean?(fields.get("stderr_truncated") or Null)
  code = fields.get("exit_code") or Null
  return bad if !nullable_integer?(code,
    false) or !nullable_integer?(fields.get("elapsed_ms") or Null, true)
  return bad if execution == "completed" and code == Null
  return bad if execution != "completed" and code != Null
  error = text(fields, "error_code") or ""
  return bad if state == "refusal" and (execution != "not_started" or error != "refused")
  return bad if state == "timeout" and (execution == "completed" or error != "timeout")
  return bad if state == "cancellation" and (execution == "completed" or error != "cancelled")
  return bad if state == "failure" and !["command_failed", "internal"].contains?(error)
  if state == "success"
    return bad if execution != "completed" or text(fields, "error_code") != Some("none")
    if code.to_i64 != Some(0)
      return Json.encode(Object(fields: fields.set("state",
        String(text: "failure")).set("error_code", String(text: "command_failed"))))
    end
  end
  return bad if state == "failure" and execution == "completed" and code.to_i64 == Some(0)
  body
end

fn boolean?(value: Json) : Bool
  value == Bool(value: true) or value == Bool(value: false)
end

fn refused?(output: String) : Bool
  case Json.decode(output)
    Ok(Object(fields)): text(fields, "state") == Some("refusal")
    Ok(_) | Error(_): false
  end
end

fn terminal?(output: String) : Bool
  case Json.decode(output)
    Ok(Object(fields)):
      text(fields, "execution") == Some("unknown") or text(fields,
        "state") == Some("timeout") or text(fields, "state") == Some("cancellation")
    Ok(_) | Error(_): true
  end
end

verified: types, contracts, tests (0), property (0 seeds), sim (not run)
          proven: not run
