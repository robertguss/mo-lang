module Agent.Check
expose Place, checked, steady, state_in

use Agent.Book{Book}
use Agent.Client{Trip, Sleeper, request_of, shown}
use Agent.Mock{Cursor, MockServer}
use Agent.Model{Model}
use Agent.Record{tool_names}
use Agent.Registry{Registry}
use Agent.Server{Acceptor}
use Agent.Shelf{Opened}

intent "Check a folder: copy its run logs into runs.check beside them, serve the folder on a free port with the scripted model on another, and play a runs file through the client, each line a request, a brief request, or a wait for a run to end, printing what came back with the clock's numbers steadied; runs.check is emptied before and after."

# What a check plays: the folder, the model's script, and the runs file.
struct Place
  dir: String
  script: String
  runs: String
end

# The transcript of a check, or why it could not be played.
fn checked(http: Http, fs: Fs, clock: Clock, err: Out, place: Place) : Result(String, String)
  script = try lines_of(fs, place.script)
  plays = try lines_of(fs, place.runs)
  folder = fs.scoped(place.dir)
  copies = try copied(folder)
  model = try served_model(http, script)
  book = Book.start(folder, clock, "runs.check", clock.now)
  case book.ask(Open, within: 60_000.ms)
    Ok(Ready(runs: _, restarted: restarted)):
      err.write_line("agent: #{copies} run logs copied into #{place.dir}/runs.check, #{restarted} left running there failed as restarted")
    Ok(Unready(why)):
      return Error("#{place.dir} #{why}")
    Error(_):
      return Error("#{place.dir} took longer than a minute to open")
  end
  registry = Registry.start(book, folder, http, clock,
    Model(host: "127.0.0.1", port: model, tools: tool_names()))
  case http.listen(0, within: 5_000.ms)
    Ok(listener):
      listener.serve(into: Acceptor.start(registry), idle: 5_000.ms)
      transcript = played(http, Sleeper.start(http), listener.port, plays)
      removed = try emptied(folder)
      err.write_line("agent: #{removed} run logs removed from #{place.dir}/runs.check")
      Ok(transcript)
    Error(_): Error("cannot listen on 127.0.0.1")
  end
end

fn lines_of(fs: Fs, path: String) : Result(List(String), String)
  case fs.read_only.read_lines(path, within: 10_000.ms)
    Ok(found): Ok(found)
    Error(_): Error("#{path} is not a file agent can read")
  end
end

# The scripted model on a free port, its port.
fn served_model(http: Http, script: List(String)) : Result(UInt16, String)
  case http.listen(0, within: 5_000.ms)
    Ok(listener):
      listener.serve(into: MockServer.start(Cursor.start(script), http), idle: 60_000.ms)
      Ok(listener.port)
    Error(_): Error("cannot listen on 127.0.0.1 for the scripted model")
  end
end

# runs.check holding a copy of each log in runs, and nothing else: the logs copied.
fn copied(folder: Fs) : Result(UInt64, String)
  try emptied(folder)
  names = case folder.scoped("runs").list(within: 10_000.ms)
    Ok(found): found
    Error(_): []
  end
  for name in names
    case folder.read("runs/#{name}", within: 10_000.ms)
      Ok(text):
        if folder.write("runs.check/#{name}", text, within: 10_000.ms) is Error(_)
          return Error("cannot copy runs/#{name} into runs.check")
        end
      Error(_):
        return Error("cannot read runs/#{name}")
    end
  end
  Ok(names.size)
end

# runs.check made when it is not there, and emptied: the files removed.
fn emptied(folder: Fs) : Result(UInt64, String)
  if folder.mkdir("runs.check", within: 10_000.ms) is Error(_)
    return Error("cannot make runs.check")
  end
  case folder.scoped("runs.check").list(within: 10_000.ms)
    Ok(names):
      for name in names
        if folder.remove("runs.check/#{name}", within: 10_000.ms) is Error(_)
          return Error("cannot empty runs.check")
        end
      end
      Ok(names.size)
    Error(_): Error("cannot list runs.check")
  end
end

# Each line played, and what came back, with the clock's numbers steadied.
fn played(http: Http, sleeper: Handle(Sleeper), port: UInt16, lines: List(String)) : String
  var transcript = ""
  for line in lines
    transcript = "#{transcript}> #{line}\n#{heard(http, sleeper, port, line)}"
  end
  transcript
end

fn heard(http: Http, sleeper: Handle(Sleeper), port: UInt16, line: String) : String
  words = line.split(" ")
  if words.first == Some("wait") and words.size == 3
    return waited(http, sleeper,
      Trip(host: "127.0.0.1", port: port, token: words.get(1) or "", method: "GET",
      path: "/runs/#{words.get(2) or ""}", json: ""))
  end
  brief = words.first == Some("brief")
  asked = if brief
    words.drop(1)
  else
    words
  end
  case trip_of(asked, port)
    Some(trip):
      case http.send(request_of(trip), host: trip.host, port: trip.port, within: 10_000.ms)
        Ok(response): briefly(response, brief)
        Error(_): "no agent answered at 127.0.0.1:#{port}\n"
      end
    None: "a line is a token, a method, a path, and any JSON\n"
  end
end

fn trip_of(words: List(String), port: UInt16) : Option(Trip)
  return None if words.size < 3
  Some(Trip(host: "127.0.0.1", port: port, token: words.first or "", method: words.get(1) or "",
    path: words.get(2) or "", json: String.join(words.drop(3), " ")))
end

# A response in full with its clock's numbers steadied, or, for a brief line, its status and its
# run's state alone.
fn briefly(response: Response, brief: Bool) : String
  return steady(shown(response)) if !brief
  "#{response.status} #{state_in(response.body)}\n"
end

# The run's state once it is no longer running, asking every 10 ms for at most 30 seconds.
fn waited(http: Http, sleeper: Handle(Sleeper), trip: Trip) : String
  for _ in 0..3_000
    case http.send(request_of(trip), host: trip.host, port: trip.port, within: 10_000.ms)
      Ok(response):
        if response.status != 200 or state_in(response.body) != "running"
          return "#{response.status} #{state_in(response.body)}\n"
        end
      Error(_):
        return "no agent answered at 127.0.0.1:#{trip.port}\n"
    end
    if sleeper.ask(Nap(ms: 10), within: 10_000.ms) is Error(_)
      return "the sleeper did not wake\n"
    end
  end
  "still running after 30 seconds\n"
end

# The state a run's JSON names, or "".
fn state_in(body: String) : String
  label = "\"state\": \""
  at = body.index_of(label) or body.size
  rest = body.slice(at + label.size, body.size)
  rest.slice(0, rest.index_of("\"") or 0)
end

# A transcript with what depends on the clock replaced: a run's times, a step's time, and the
# service's uptime.
fn steady(text: String) : String
  times = masked(masked(text, "created_at", true), "updated_at", true)
  masked(masked(times, "took_ms", false), "uptime_ms", false)
end

fn masked(text: String, key: String, quoted: Bool) : String
  label = "\"#{key}\": "
  pieces = text.split(label)
  mark = if quoted
    "\"<#{key}>\""
  else
    "<#{key}>"
  end
  rest = pieces.drop(1).map(fn(piece) "#{label}#{mark}#{after_value(piece, quoted)}" end)
  String.join([pieces.first or ""].concat(rest), "")
end

# What follows a JSON value at the start of a piece: past the closing quote of a string, or from
# the first , or } after a number.
fn after_value(piece: String, quoted: Bool) : String
  if quoted
    inside = piece.slice(1, piece.size)
    return inside.slice((inside.index_of("\"") or 0) + 1, inside.size)
  end
  ends = [piece.index_of(","), piece.index_of("}")].flat_map(fn(at) found(at) end)
  piece.slice(ends.min or piece.size, piece.size)
end

fn found(at: Option(UInt64)) : List(UInt64)
  case at
    Some(i): [i]
    None: []
  end
end

test "the clock's numbers are steadied, and a brief line keeps the status and the state"
  run = "{\"id\": \"r_1\", \"state\": \"done\", \"created_at\": \"2026-09-14T10:00:00.123Z\", \"updated_at\": \"x\"}"
  assert steady(run) == "{\"id\": \"r_1\", \"state\": \"done\", \"created_at\": \"<created_at>\", \"updated_at\": \"<updated_at>\"}"
  assert steady("{\"n\": 1, \"took_ms\": 12, \"refused\": false}") == "{\"n\": 1, \"took_ms\": <took_ms>, \"refused\": false}"
  assert steady("{\"cancelled\": 0, \"uptime_ms\": 1234}") == "{\"cancelled\": 0, \"uptime_ms\": <uptime_ms>}"
  assert state_in(run) == "done" and state_in("{}") == ""
  assert briefly(Response(status: 200, body: run), true) == "200 done\n"
  assert trip_of(["ada", "POST", "/runs", "{\"goal\":", "\"g\"}"],
    1) == Some(Trip(host: "127.0.0.1", port: 1, token: "ada", method: "POST", path: "/runs",
    json: "{\"goal\": \"g\"}"))
  assert trip_of(["ada", "GET"], 1) is None
end

verified: types, contracts, tests (1), property (0 seeds), sim (not run)
          proven: not run
