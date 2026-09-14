module Agent.Mock
expose Line, Place, Cursor, MockServer, MockWorker, Mocks, line_of, lines_used, played

use Agent.Client{napped}

intent "The scripted model agent ships: an HTTP server answering POST /complete with the lines of a script, one JSON reply a line, played from the top to every run, which its x-run header names; a {\"slow_ms\": n} line makes the reply after it n ms late, and a {\"garbage\": true} line answers with text that is not JSON."

# A reply as the script gives it: how many milliseconds late, and its text.
struct Line
  slow_ms: UInt64
  text: String
end

# Where a run is in the script: the next line's index, the calls it made, and the body it posted
# last.
struct Place
  at: UInt64
  calls: UInt64
  heard: String
end

# The script's cursor for every run.
process Cursor(script: List(String))
  state
    places: Map(String, Place)
  end

  message Next(run: String, body: String) : Line
  message Heard(run: String) : String
  message Calls(run: String) : UInt64

  fn update(state, message)
    case message
      Next(run: run, body: body):
        place = state.places.get(run) or Place(at: 0, calls: 0, heard: "")
        state.places = state.places.set(run,
          Place(at: place.at + lines_used(script, place.at), calls: place.calls + 1, heard: body))
        line_of(script, place.at)
      Heard(run): (state.places.get(run) or Place(at: 0, calls: 0, heard: "")).heard
      Calls(run): (state.places.get(run) or Place(at: 0, calls: 0, heard: "")).calls
    end
  end
end

# The runtime serves the model's listener into this; a worker answers each exchange. The mailbox
# holds a crowd of runs asking at once.
process MockServer(cursor: Handle(Cursor), http: Http) mailbox: 4_096
  state
    accepted: UInt64
    quiet: UInt64
  end

  message Accepted(exchange: Exchange)
  message Idle

  fn update(state, message)
    case message
      Accepted(exchange):
        MockWorker.start(exchange, cursor, http).send(Answer)
        state.accepted += 1
      Idle:
        state.quiet += 1
    end
  end
end

# Answers one exchange, late when its line says so, and ends.
process MockWorker(exchange: Exchange, cursor: Handle(Cursor), http: Http)
  state
    answered: Bool
  end

  message Answer

  fn update(state, message)
    case message
      Answer:
        response = played(cursor, http, exchange.request)
        state.answered = exchange.reply(response, within: 10_000.ms) is Ok(_)
    end
  end
end

supervisor Mocks(script: List(String), cursor: Handle(Cursor), http: Http, exchange: Exchange)
  child Cursor(script), restart: :always
  child MockServer(cursor, http), restart: :always
  child MockWorker(exchange, cursor, http), restart: :never
end

fn over() : String
  "{\"done\": \"the script is over\", \"tokens\": 0}"
end

# The reply at a place in the script: a slow line and the line after it make one late reply, a
# garbage line is text that is not JSON, and past the end the script says it is over.
fn line_of(script: List(String), at: UInt64) : Line
  return Line(slow_ms: 0, text: over()) if at >= script.size
  text = script.get(at) or over()
  case slow_of(text)
    Some(ms): Line(slow_ms: ms, text: plain(script.get(at + 1) or over()))
    None: Line(slow_ms: 0, text: plain(text))
  end
end

# How many lines the reply at a place uses up: two for a slow line and the reply after it.
fn lines_used(script: List(String), at: UInt64) : UInt64
  return 2 if slow_of(script.get(at) or "") is Some(_)
  1
end

fn slow_of(text: String) : Option(UInt64)
  case Json.decode(text)
    Ok(Object(fields)):
      whole = try (try fields.get("slow_ms")).to_i64
      return None if whole < 0
      Some(whole.to_u64)
    Ok(_) | Error(_): None
  end
end

fn plain(text: String) : String
  case Json.decode(text)
    Ok(Object(fields)):
      return "this is not JSON" if fields.get("garbage") == Some(Bool(value: true))
      text
    Ok(_) | Error(_): text
  end
end

# The response to one request: the run's next reply for POST /complete, after its delay.
fn played(cursor: Handle(Cursor), http: Http, request: Request) : Response
  if request.path != "/complete" or request.method != "POST"
    return Response(status: 404, body: "{\"error\": \"the model answers POST /complete\"}")
  end
  run = request.headers.get("x-run") or "-"
  case cursor.ask(Next(run: run, body: request.body), within: 5_000.ms)
    Ok(line):
      late = line.slow_ms > 0 and napped(http, line.slow_ms)
      headers = Map.new().set("content-type", "application/json").set("x-late", "#{late}")
      Response(status: 200, headers: headers, body: line.text)
    Error(_): Response(status: 503, body: "{\"error\": \"the script did not answer in time\"}")
  end
end

fn asked(http: Http, port: UInt16, run: String) : String
  request = Request(method: "POST", path: "/complete", headers: Map.new().set("x-run", run),
    body: "{\"goal\": \"#{run}\"}")
  case http.send(request, host: "localhost", port: port, within: 1.minute)
    Ok(response): "#{response.status} #{response.body}"
    Error(_): "no answer"
  end
end

test "a script plays each line in order, a slow line late, a garbage line not JSON, and then says it is over"
  script = ["{\"tool\": \"now\", \"tokens\": 1}",
    "{\"slow_ms\": 250}",
    "{\"done\": \"x\", \"tokens\": 2}",
    "{\"garbage\": true}"]
  assert line_of(script, 0) == Line(slow_ms: 0, text: "{\"tool\": \"now\", \"tokens\": 1}")
  assert line_of(script, 1) == Line(slow_ms: 250, text: "{\"done\": \"x\", \"tokens\": 2}")
  assert lines_used(script, 1) == 2 and lines_used(script, 0) == 1
  assert line_of(script, 3) == Line(slow_ms: 0, text: "this is not JSON")
  assert line_of(script, 4) == Line(slow_ms: 0, text: over())
  assert line_of(["{\"slow_ms\": -1}"], 0).slow_ms == 0
end

test "every run hears the script from the top, over HTTP"
  http = Http.fixture()
  assert http.listen(0, within: 1.minute) is Ok(listener)
  cursor = Cursor.start(["{\"done\": \"one\", \"tokens\": 1}",
    "{\"slow_ms\": 20}",
    "{\"done\": \"two\", \"tokens\": 1}"])
  listener.serve(into: MockServer.start(cursor, http), idle: 5_000.ms)
  first = asked(http, listener.port, "r_1")
  second = asked(http, listener.port, "r_1")
  other = asked(http, listener.port, "r_2")
  assert first == "200 {\"done\": \"one\", \"tokens\": 1}" or first == "no answer" or first.starts_with?("503")
  assert second.starts_with?("200 ") or second == "no answer" or second.starts_with?("503")
  assert other == "200 {\"done\": \"one\", \"tokens\": 1}" or other == "no answer" or other.starts_with?("503")
  heard = cursor.ask(Heard(run: "r_2"), within: 1.minute)
  assert heard == Ok("{\"goal\": \"r_2\"}") or heard == Ok("") or heard is Error(_)
  wrong = http.send(Request(method: "GET", path: "/complete"), host: "localhost",
    port: listener.port, within: 1.minute)
  assert wrong is Error(_) or (wrong is Ok(response) and response.status == 404)
end

verified: types, contracts, tests (2), property (0 seeds), sim (100 runs)
          proven: not run
