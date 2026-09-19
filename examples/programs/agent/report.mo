module Agent.Report
expose report, reporting_error

use Agent.Record{Record, Status, status_name}

intent "Render recorded fixture steps and one recorded terminal result as JSONL; synthetic zero, unknown failed-call usage and tool usage are distinct."

fn envelope(id: String, event: String, n: UInt64, payload: String) : String
  "{\"schema\": \"mo-coding-fixture-v1\", \"run_id\": #{Json.encode(id)}, \"event\": #{Json.encode(event)}, \"step_number\": #{n}, \"payload\": #{payload}}\n"
end

fn reporting_error(id: String, why: String) : String
  envelope(id, "reporting_error", 0, "{\"error\": #{Json.encode(why)}}")
end

fn report(record: Record, steps: List(String)) : Result(String, String)
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
    lines = "#{lines}#{envelope(record.id, kind, number, payload)}"
  end
  return Error("incomplete recorded transcript") if model_calls != record.steps_taken
  total = if complete: "#{record.tokens_used}" else: "null"
  terminal = "{\"state\": #{Json.encode(status_name(record.status))}, \"result\": #{Json.encode(record.answer)}, \"error\": #{Json.encode(record.why)}, \"usage\": #{Json.encode(if complete: "reported_synthetic" else: "unknown")}, \"tokens\": #{total}}"
  Ok("#{lines}#{envelope(record.id, "terminal", number, terminal)}")
end

fn text(fields: Map(String, Json), key: String) : String
  case fields.get(key)
    Some(String(value)): value
    Some(_) | None: ""
  end
end

verified: types, contracts, tests (0), property (0 seeds), sim (not run)
          proven: not run
