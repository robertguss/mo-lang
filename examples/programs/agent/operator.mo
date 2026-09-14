module Agent.Operator
expose Operator, Operators, View, viewed, tool_of, last_message

intent "The operator's view of a running agent, from the runtime surface alone and held read-only: GET /runs names each run's process, the run it is and the step it is on as its state last read showed them, what it is doing, and the call it waits in; GET /slowest names the slowest tool update of the last minute and the call it waited longest in; GET /inflight counts the model calls in flight."

# What a view answered, and the run ids known by process, which a view learns whenever it reads a
# run's state between two of its updates.
struct View
  response: Response
  known: Map(UInt64, String)
end

# Answers each exchange in its own update: every row it reads is the runtime's, taken between the
# program's updates.
process Operator(runtime: Runtime, clock: Clock) mailbox: 1_024
  state
    known: Map(UInt64, String)
    answered: UInt64
    quiet: UInt64
  end

  message Accepted(exchange: Exchange)
  message Idle

  fn update(state, message)
    case message
      Accepted(exchange):
        view = viewed(runtime, clock, state.known, exchange.request)
        state.known = view.known
        if exchange.reply(view.response, within: 10_000.ms) is Ok(_)
          state.answered += 1
        end
      Idle:
        state.quiet += 1
    end
  end
end

supervisor Operators(runtime: Runtime, clock: Clock)
  child Operator(runtime, clock), restart: :always
end

fn viewed(runtime: Runtime, clock: Clock, known: Map(UInt64, String), request: Request) : View
  if request.method != "GET"
    return View(response: json(405, "{\"error\": \"the operator's view takes GET\"}"), known: known)
  end
  case request.path
    "/runs": runs_view(runtime, known)
    "/slowest": View(response: json(200, slowest(runtime, clock)), known: known)
    "/inflight": View(response: json(200, inflight(runtime)), known: known)
    _:
      View(response: json(404,
        "{\"error\": \"the operator's view has /runs, /slowest, and /inflight\"}"),
        known: known)
  end
end

fn json(status: UInt16, body: String) : Response
  Response(status: status, headers: Map.new().set("content-type", "application/json"), body: body)
end

# Each live run process: its id, the run and step its state showed when last read (a run waiting in
# a call is read only once the call ends, so the run is the one learned before), what its last update
# says it is doing now, and the call it waits in. Every run's last update is read first, right after
# the list, so what a run is doing agrees with the call the list shows it waiting in; the states,
# which may each wait 20 ms, are read after.
fn runs_view(runtime: Runtime, known: Map(UInt64, String)) : View
  runs = runtime.processes(within: 5_000.ms).filter(fn(info) info.name == "Run" and info.alive end)
  var doings = [""].take(0)
  for info in runs
    doings = doings.push(doing_after(last_message(runtime.recent(info.id, 16, within: 1_000.ms))))
  end
  var learned = known
  var rows = [""].take(0)
  for pair in runs.zip(doings)
    read = case runtime.state(pair.0.id, within: 20.ms)
      Ok(text): text
      Error(_): ""
    end
    run = quoted_after(read, "id: \"")
    if run != ""
      learned = learned.set(pair.0.id, run)
    end
    rows = rows.push(run_row(pair.0, learned.get(pair.0.id) or "", word_after(read, ", n: "),
      pair.1))
  end
  View(response: json(200, "{\"runs\": [#{String.join(rows, ", ")}]}"), known: learned)
end

fn run_row(info: ProcessInfo, run: String, step: String, doing: String) : String
  waiting = Json.encode(info.waiting_in)
  shown_step = if step == ""
    "null"
  else
    step
  end
  "{\"process\": #{info.id}, \"run\": #{Json.encode(run)}, \"step\": #{shown_step}, \"doing\": #{Json.encode(doing)}, \"waiting_in\": #{waiting}}"
end

# The text after a label up to the next quote.
fn quoted_after(text: String, label: String) : String
  at = text.index_of(label) or text.size
  rest = text.slice(at + label.size, text.size)
  rest.slice(0, rest.index_of("\"") or 0)
end

# The word after a label, up to the next comma or parenthesis.
fn word_after(text: String, label: String) : String
  at = text.index_of(label) or text.size
  rest = text.slice(at + label.size, text.size)
  ends = [rest.index_of(","), rest.index_of(")")].flat_map(fn(i) found(i) end)
  rest.slice(0, ends.min or 0)
end

fn found(at: Option(UInt64)) : List(UInt64)
  case at
    Some(i): [i]
    None: []
  end
end

# What a run is doing, from the message of the update it took last.
fn doing_after(last: String) : String
  case last
    "Begin" | "Acted": "asking the model"
    "Think": "writing its model step"
    "Thought": "using a tool"
    "Act": "writing its tool step"
    "Close": "stopped"
    _: "starting"
  end
end

# The message of the last update among a process's events, or "".
fn last_message(events: List(Event)) : String
  updates = events.flat_map(fn(event) update_message(event) end)
  updates.last or ""
end

# The message an update took, by pattern (step 24 renamed Updated's fields off the keywords).
fn update_message(event: Event) : List(String)
  if event is Updated(at: _, pid: _, name: _, taking: taking, took_us: _, waited_us: _, longest: _)
    return [taking]
  end
  []
end

# A run's tool update: how long it took, and the call it waited longest in.
fn tool_update(event: Event) : List((UInt64, String))
  if event is Updated(at: _, pid: _, name: name, taking: taking, took_us: took, waited_us: _,
    longest: longest)
    return [(took, longest)] if name == "Run" and taking == "Act"
  end
  []
end

# The slowest tool update of the last minute in the runtime's ring of events.
fn slowest(runtime: Runtime, clock: Clock) : String
  events = runtime.events(since: clock.now - 1.minute, n: 4_096, within: 5_000.ms)
  tools = events.flat_map(fn(event) tool_update(event) end).sort_by_desc(fn(pair) pair.0 end)
  case tools.first
    Some(slow):
      "{\"tool\": #{Json.encode(tool_of(slow.1))}, \"call\": #{Json.encode(slow.1)}, \"took_us\": #{slow.0}, \"updates\": #{tools.size}}"
    None: "{\"tool\": null, \"call\": null, \"took_us\": 0, \"updates\": 0}"
  end
end

# The tool a run's update was using, from the call it waited longest in.
fn tool_of(call: String) : String
  case call
    "Fs.list": "list_files"
    "Fs.size" | "Fs.read": "read_file"
    "Fs.read_lines": "search"
    "Fs.write": "write_file"
    "Http.send": "http_get"
    "": "now"
    _: call
  end
end

# Model calls in flight: run processes waiting in Http.send whose last update was not the one
# before a tool; and beside them the http_get calls and every run process.
fn inflight(runtime: Runtime) : String
  var model = 0
  var gets = 0
  var runs = 0
  for info in runtime.processes(within: 5_000.ms)
    if info.name == "Run" and info.alive
      runs += 1
      calls = calls_of(runtime, info)
      model += calls.0
      gets += calls.1
    end
  end
  "{\"model_calls\": #{model}, \"http_gets\": #{gets}, \"runs\": #{runs}}"
end

# A run process's calls in flight: a model call when it waits in Http.send and its last update was
# not the one before a tool, and an http_get when it was.
fn calls_of(runtime: Runtime, info: ProcessInfo) : (UInt64, UInt64)
  return (0, 0) if info.waiting_in != Some("Http.send")
  return (0, 1) if last_message(runtime.recent(info.id, 16, within: 1_000.ms)) == "Thought"
  (1, 0)
end

test "a view reads a run's step from its state, and names a tool by the call it waited in"
  shown = "Run(run: Progress(id: \"r_3\", by: None, phase: Asking, steps: [], n: 4, taken: 2))"
  assert quoted_after(shown, "id: \"") == "r_3" and word_after(shown, ", n: ") == "4"
  assert quoted_after("", "id: \"") == "" and word_after("", ", n: ") == ""
  assert tool_of("Fs.read_lines") == "search" and tool_of("Http.send") == "http_get"
  assert doing_after("Acted") == "asking the model" and doing_after("Thought") == "using a tool"
  runtime = Runtime.fixture()
  view = viewed(runtime, Clock.fixture(), Map.new(), Request(method: "GET", path: "/runs"))
  assert view.response.status == 200 and view.response.body == "{\"runs\": []}"
  assert viewed(runtime, Clock.fixture(), Map.new(),
    Request(method: "GET",
    path: "/inflight")).response.body == "{\"model_calls\": 0, \"http_gets\": 0, \"runs\": 0}"
  assert viewed(runtime, Clock.fixture(), Map.new(),
    Request(method: "GET", path: "/nothing")).response.status == 404
  assert viewed(runtime, Clock.fixture(), Map.new(),
    Request(method: "POST", path: "/runs")).response.status == 405
end

verified: types, contracts, tests (1), property (0 seeds), sim (not run)
          proven: not run
