module Agent.Report
expose report, reporting_error, application_report, application_error

use Agent.Record{Record, Status, status_name}

intent "Render recorded fixture steps and one recorded terminal result as JSONL; synthetic zero, unknown failed-call usage and tool usage are distinct. The application workspace report is the same rendering under its own versioned schema, after a line of its fixed profile caps."

fn fixture_schema() : String
  "mo-coding-fixture-v1"
end

fn application_schema() : String
  "mo-application-workspace-v1"
end

fn envelope(schema: String, id: String, event: String, n: UInt64, payload: String) : String
  "{\"schema\": #{Json.encode(schema)}, \"run_id\": #{Json.encode(id)}, \"event\": #{Json.encode(event)}, \"step_number\": #{n}, \"payload\": #{payload}}\n"
end

fn reporting_error(id: String, why: String) : String
  envelope(fixture_schema(), id, "reporting_error", 0, "{\"error\": #{Json.encode(why)}}")
end

# An application run that has no terminal report to give: why, and whether earlier writes to its
# log are proved or uncertain.
fn application_error(id: String, why: String, persistence: String) : String
  envelope(application_schema(), id, "reporting_error", 0,
    "{\"error\": #{Json.encode(why)}, \"persistence\": #{Json.encode(persistence)}}")
end

fn report(record: Record, steps: List(String)) : Result(String, String)
  rendered(fixture_schema(), record, steps)
end

# The profile line (its caps as JSON), then the recorded steps and terminal result.
fn application_report(record: Record, steps: List(String), profile: String) : Result(String, String)
  body = try rendered(application_schema(), record, steps)
  Ok("#{envelope(application_schema(), record.id, "profile", 0, profile)}#{body}")
end

fn rendered(schema: String, record: Record, steps: List(String)) : Result(String, String)
  return Error("run has no recorded terminal result") if record.status == Running
  var lines = ""
  # Cancellation can win before an in-flight call is recorded; no total is complete.
  var complete = record.status != Cancelled and record.why != Some("recording_failure")
  var number = 0.to_u64
  var model_calls = 0.to_u64
  for step in steps
    fields = case Json.decode(step)
      Ok(Object(found)): found
      Ok(_) | Error(_):
        return Error("invalid recorded step")
    end
    kind = text(fields, "kind")
    if kind == "model"
      model_calls += 1
    end
    output = text(fields, "result")
    n = (fields.get("n") or Null).to_i64 or -1
    return Error("invalid step sequence") if n < 1 or n.to_u64 != number + 1
    number = n.to_u64
    structured = case Json.decode(output)
      Ok(value): value
      Error(_): String(text: output)
    end
    known = kind == "model" and output.starts_with?("{\"tool\":") or kind == "model" and output.starts_with?("{\"done\":")
    usage = if kind == "tool": "not_applicable" else: if known: "reported_synthetic" else: "unknown"
    if kind == "model" and !known
      complete = false
    end
    tokens = if known: Json.encode(fields.get("tokens") or Null) else: "null"
    payload = "{\"step\": #{step}, \"result\": #{Json.encode(structured)}, \"usage\": #{Json.encode(usage)}, \"tokens\": #{tokens}}"
    lines = "#{lines}#{envelope(schema, record.id, kind, number, payload)}"
  end
  return Error("incomplete recorded transcript") if model_calls != record.steps_taken
  total = if complete: "#{record.tokens_used}" else: "null"
  terminal = "{\"state\": #{Json.encode(status_name(record.status))}, \"result\": #{Json.encode(record.answer)}, \"error\": #{Json.encode(record.why)}, \"usage\": #{Json.encode(if complete: "reported_synthetic" else: "unknown")}, \"tokens\": #{total}}"
  Ok("#{lines}#{envelope(schema, record.id, "terminal", number, terminal)}")
end

fn text(fields: Map(String, Json), key: String) : String
  case fields.get(key)
    Some(String(value)): value
    Some(_) | None: ""
  end
end

verified: types, contracts, tests (0), property (0 seeds), sim (not run)
          proven: not run
