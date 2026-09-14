module Agent.Transcript
expose Step, Replayed, Seen, step_json, header_line, step_line, end_line, unreplayed, replayed, steps_of, log_of

use Agent.Record{Order, Record, Status, default_budget, record, status_name, status_named}

intent "The append-only log of a run, <runs>/<id>.log, one JSON object a line: the run as it was ordered, a line for each model call and tool call, and the one line that ends it; replayed into the run's record, and read back as the run's steps."

# One model call or one tool call as the transcript holds it. Its result is `output`, since
# result is a keyword.
struct Step
  n: UInt64
  kind: String
  name: String
  args: Map(String, String)
  output: String
  tokens: UInt64
  took_ms: UInt64
  refused: Bool
end

# The steps read back so far: the number of the last, and each as the API shows it.
struct Seen
  n: UInt64
  steps: List(String)
end

# A log replayed so far: the run once its first line is read, the number of the last step read,
# whether a line ended it, and the lines that were not the log's.
struct Replayed
  run: Option(Record)
  steps: UInt64
  ended: Bool
  bad: UInt64
end

# A step as the API shows it, the spec's fields in its order.
fn step_json(step: Step) : String
  head = "{\"n\": #{step.n}, \"kind\": #{Json.encode(step.kind)}, \"name\": #{Json.encode(step.name)}, \"args\": #{Json.encode(step.args)}"
  "#{head}, \"result\": #{Json.encode(step.output)}, \"tokens\": #{step.tokens}, \"took_ms\": #{step.took_ms}, \"refused\": #{step.refused}}"
end

# The first line of a run's log: who ordered it, and what.
fn header_line(run: Record, order: Order) : String
  who = "\"id\": #{Json.encode(run.id)}, \"owner\": #{Json.encode(run.owner)}"
  what = "\"goal\": #{Json.encode(order.goal)}, \"folder\": #{Json.encode(order.folder)}, \"tools\": #{Json.encode(order.tools)}, \"hosts\": #{Json.encode(order.hosts)}, \"budget\": #{Json.encode(order.budget)}"
  "{\"at\": #{Json.encode(run.created_at)}, \"run\": {#{who}, #{what}}}\n"
end

fn step_line(at: Time, step: Step) : String
  "{\"at\": #{Json.encode(at)}, \"step\": #{step_json(step)}}\n"
end

# The line that ends a run: its final state, and its result or its error.
fn end_line(at: Time, status: Status, answer: Option(String), why: Option(String)) : String
  requires status != Running

  ends = "\"state\": \"#{status_name(status)}\", \"result\": #{Json.encode(answer)}, \"error\": #{Json.encode(why)}"
  "{\"at\": #{Json.encode(at)}, \"end\": {#{ends}}}\n"
end

fn unreplayed() : Replayed
  Replayed(run: None, steps: 0, ended: false, bad: 0)
end

# One more line of a log. A step counts toward steps_taken when it is a model call, and its
# tokens toward tokens_used; the first end line settles the state, and a step after it (the call
# in flight when a cancel was written) is kept without changing it. A line that is not the log's,
# such as a last line cut short, is counted and left out; a step whose number the log held already
# (written again after an append that timed out) is left out too.
fn replayed(so_far: Replayed, line: String) : Replayed
  var next = so_far
  fields = case Json.decode(line)
    Ok(Object(fields)): fields
    Ok(_) | Error(_): Map.new()
  end
  at = time_in(fields, "at")
  case (fields.get("run"), fields.get("step"), fields.get("end"), at)
    (Some(Object(run)), None, None, Some(time)):
      next.run = header_of(run, time)
    (None, Some(Object(step)), None, Some(time)):
      if count_in(step, "n") > so_far.steps
        next.run = stepped(so_far.run, step, time)
        next.steps = count_in(step, "n")
      end
    (None, None, Some(Object(ending)), Some(time)):
      next.run = ended(so_far, ending, time)
      next.ended = so_far.ended or next.run != so_far.run
    _:
      next.bad = so_far.bad + 1
  end
  next
end

fn header_of(run: Map(String, Json), at: Time) : Option(Record)
  id = try text_in(run, "id")
  Some(record(id, try text_in(run, "owner"), try text_in(run, "goal"), at))
end

fn stepped(run: Option(Record), step: Map(String, Json), at: Time) : Option(Record)
  var after = try run
  after.updated_at = at
  return Some(after) if text_in(step, "kind") != Some("model")
  after.steps_taken = after.steps_taken + 1
  after.tokens_used = after.tokens_used + count_in(step, "tokens")
  Some(after)
end

fn ended(so_far: Replayed, ending: Map(String, Json), at: Time) : Option(Record)
  var after = try so_far.run
  return Some(after) if so_far.ended
  after.status = try status_named(try text_in(ending, "state"))
  after.answer = text_in(ending, "result")
  after.why = text_in(ending, "error")
  after.updated_at = at
  Some(after)
end

# The steps a log holds, each as the API shows it: the object after "step": on each step line,
# as it was written, once for each step number.
fn steps_of(lines: List(String)) : List(String)
  lines.reduce(Seen(n: 0, steps: []), fn(seen, line) seen_step(seen, line) end).steps
end

fn seen_step(seen: Seen, line: String) : Seen
  marker = ", \"step\": "
  return seen if !line.contains?(marker) or !line.ends_with?("}")
  n = case Json.decode(line)
    Ok(Object(fields)): step_number(fields)
    Ok(_) | Error(_): 0
  end
  return seen if n <= seen.n
  text = line.slice((line.index_of(marker) or 0) + marker.size, line.size - 1)
  Seen(n: n, steps: seen.steps.push(text))
end

fn step_number(fields: Map(String, Json)) : UInt64
  case fields.get("step")
    Some(Object(step)): count_in(step, "n")
    Some(_) | None: 0
  end
end

# A run's log, in the runs folder.
fn log_of(runs: String, id: String) : String
  "#{runs}/#{id}.log"
end

fn text_in(fields: Map(String, Json), name: String) : Option(String)
  case fields.get(name)
    Some(String(text)): Some(text)
    Some(_) | None: None
  end
end

fn time_in(fields: Map(String, Json), name: String) : Option(Time)
  Time.parse(try text_in(fields, name))
end

fn count_in(fields: Map(String, Json), name: String) : UInt64
  whole = (fields.get(name) or Null).to_i64 or 0
  return 0 if whole < 0
  whole.to_u64
end

fn order_of() : Order
  Order(goal: "count the notes", folder: "work", tools: ["list_files"], hosts: [],
    budget: default_budget())
end

fn tool_step(n: UInt64) : Step
  Step(n: n, kind: "tool", name: "list_files", args: Map.new().set("path", "."),
    output: "a.txt\nb.txt", tokens: 0, took_ms: 3, refused: false)
end

fn model_step(n: UInt64, tokens: UInt64) : Step
  Step(n: n, kind: "model", name: "model", args: Map.new(), output: "{\"tool\": \"list_files\"}",
    tokens: tokens, took_ms: 2, refused: false)
end

test "a step is shown with the spec's fields in order"
  assert step_json(tool_step(2)) == "{\"n\": 2, \"kind\": \"tool\", \"name\": \"list_files\", \"args\": {\"path\": \".\"}, \"result\": \"a.txt\\nb.txt\", \"tokens\": 0, \"took_ms\": 3, \"refused\": false}"
end

test "a log replays into its run: steps and tokens from the model calls, and the state from its end"
  at = Time.fixture()
  run = record("r_3", "ada", "count the notes", at)
  lines = [header_line(run, order_of()),
    step_line(at + 5.ms, model_step(1, 40)),
    step_line(at + 9.ms, tool_step(2)),
    step_line(at + 12.ms, model_step(3, 2)),
    end_line(at + 20.ms, Done, Some("2 notes"), None)]
  text = String.join(lines, "")
  back = text.lines.reduce(unreplayed(), fn(r, line) replayed(r, line) end)
  assert back.steps == 3 and back.ended and back.bad == 0
  case back.run
    Some(done):
      assert done.id == "r_3" and done.owner == "ada" and done.status == Done
      assert done.steps_taken == 2 and done.tokens_used == 42
      assert done.answer == Some("2 notes") and done.why is None
      assert done.created_at == at and done.updated_at == at + 20.ms
    None:
      assert false
  end
  assert steps_of(text.lines) == [step_json(model_step(1, 40)),
    step_json(tool_step(2)),
    step_json(model_step(3, 2))]
end

test "the first end settles the state, and a line that is not the log's is left out"
  at = Time.fixture()
  run = record("r_4", "ada", "g", at)
  lines = [header_line(run, order_of()),
    end_line(at, Cancelled, None, Some("cancelled by ada")),
    step_line(at + 1.ms, tool_step(1)),
    end_line(at + 2.ms, Done, Some("x"), None),
    "{\"at\": \"20"]
  back = lines.reduce(unreplayed(), fn(r, line) replayed(r, String.join(line.lines, "")) end)
  assert back.bad == 1 and back.steps == 1 and back.ended
  assert back.run is Some(cancelled)
  assert cancelled.status == Cancelled and cancelled.why == Some("cancelled by ada")
  assert cancelled.answer is None
  assert unreplayed().run is None
  assert log_of("runs", "r_4") == "runs/r_4.log"
end

test "a step written twice, after an append that timed out, replays and reads back once"
  at = Time.fixture()
  run = record("r_5", "ada", "g", at)
  lines = [header_line(run, order_of()),
    step_line(at, model_step(1, 10)),
    step_line(at, model_step(1, 10)),
    step_line(at, tool_step(2))]
  back = lines.reduce(unreplayed(), fn(r, line) replayed(r, String.join(line.lines, "")) end)
  assert back.steps == 2 and back.bad == 0
  assert back.run is Some(held)
  assert held.steps_taken == 1 and held.tokens_used == 10
  assert steps_of(lines.map(fn(line) String.join(line.lines, "") end)).size == 2
end

test rejects "an end line for a run still running"
  end_line(Time.fixture(), Running, None, None)
end

verified: types, contracts, tests (5), property (0 seeds), sim (not run)
          proven: not run
