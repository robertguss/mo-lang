# run: check data/demo data/session.txt
# run: compact data/compact
# run: serve
# exit: 2
# run: serve data/nowhere
# exit: 1
# run: client 127.0.0.1 1 ada GET /notes
# exit: 1
module Notes.Main
expose Job, Place, Trip, Problem, job, steady, main

use Notes.Server{Acceptor}
use Notes.Service{Service, opening}
use Notes.Store{Table, StoreError, open, compact, cut_short?, writing_to, lines, count}

intent "Run notes: serve a folder's notes over HTTP, compact its log to one line per live key, send one request as a client, or check a folder by serving it on a free port and playing a script through the client; a usage error exits 2, and a folder or port that cannot be had exits 1."

struct Place
  dir: String
  port: UInt16
end

# One request from the client: where to, the token (- for none), and the request.
struct Trip
  host: String
  port: UInt16
  token: String
  method: String
  path: String
  json: String
end

enum Job
  Serving(place: Place)
  Compacting(dir: String)
  Asking(trip: Trip)
  Checking(dir: String, script: String)
end

enum Problem
  Usage(detail: String)
  Unopened(dir: String, why: String)
  Unbound(port: UInt16)
  Unreached(host: String, port: UInt16)
end

fn usage() : String
  "usage: notes serve <dir> [--port N] | notes compact <dir> | notes client <host> <port> <token> <method> <path> [<json>] | notes check <dir> <script>"
end

fn job(args: List(String)) : Result(Job, Problem)
  rest = args.drop(1)
  case args.first or ""
    "serve": serving(rest)
    "compact": compacting(rest)
    "client": asking(rest)
    "check": checking(rest)
    "": Error(Usage(detail: "no command given"))
    _: Error(Usage(detail: "unknown command #{args.first or ""}"))
  end
end

fn serving(args: List(String)) : Result(Job, Problem)
  dir = try dir_of(args)
  flags = args.drop(1)
  return Ok(Serving(place: Place(dir: dir, port: 7_800))) if flags.size == 0
  if flags.size != 2 or flags.first != Some("--port")
    return Error(Usage(detail: "serve takes a folder and then --port N"))
  end
  port = try port_of(flags.get(1) or "")
  Ok(Serving(place: Place(dir: dir, port: port)))
end

fn compacting(args: List(String)) : Result(Job, Problem)
  dir = try dir_of(args)
  return Error(Usage(detail: "compact takes one folder")) if args.size != 1
  Ok(Compacting(dir: dir))
end

fn asking(args: List(String)) : Result(Job, Problem)
  if args.size < 5
    return Error(Usage(detail: "client takes a host, a port, a token, a method, and a path"))
  end
  port = try port_of(args.get(1) or "")
  trip = try trip_of(args.drop(2), args.first or "", port)
  Ok(Asking(trip: trip))
end

# A token, a method, a path, and any JSON after them, joined by spaces as they were split.
fn trip_of(words: List(String), host: String, port: UInt16) : Result(Trip, Problem)
  if words.size < 3
    return Error(Usage(detail: "a request is a token, a method, a path, and any JSON"))
  end
  json = String.join(words.drop(3), " ")
  Ok(Trip(host: host, port: port, token: words.first or "", method: words.get(1) or "",
    path: words.get(2) or "", json: json))
end

fn checking(args: List(String)) : Result(Job, Problem)
  dir = try dir_of(args)
  return Error(Usage(detail: "check takes a folder and a script")) if args.size != 2
  Ok(Checking(dir: dir, script: args.get(1) or ""))
end

fn dir_of(args: List(String)) : Result(String, Problem)
  dir = args.first or ""
  return Error(Usage(detail: "no folder given")) if dir == "" or dir.starts_with?("-")
  Ok(dir)
end

fn port_of(text: String) : Result(UInt16, Problem)
  ensures result is Ok(port) implies port >= 1

  n = text.to_u64 or 0
  return Error(Usage(detail: "a port is a number from 1 to 65535, not #{text}")) if n < 1 or n > 65_535
  Ok(n.to_u16)
end

fn ran(http: Http, fs: Fs, clock: Clock, out: Out, err: Out, args: List(String)) : Result(String,
  Problem)
  given = try job(args)
  case given
    Serving(place): serve(http, fs, clock, out, err, place)
    Compacting(dir):
      opened = try opened_store(fs, err, dir)
      compacted(fs, dir, opened)
    Asking(trip): client(http, trip)
    Checking(dir: dir, script: script):
      lines = try script_of(fs, script)
      opened = try opened_store(fs.read_only, err, dir)
      check(http, fs, clock, opened, lines)
  end
end

# Serves a folder until notes is stopped. A log whose last line was cut short is compacted
# first, so the next change starts on a line of its own.
fn serve(http: Http, fs: Fs, clock: Clock, out: Out, err: Out, place: Place) : Result(String,
  Problem)
  opened = try opened_store(fs, err, place.dir)
  whole = if cut_short?(opened)
    try compacted_store(fs, place.dir, opened)
  else
    opened
  end
  case http.listen(place.port, within: 5_000.ms)
    Ok(listener): Ok(served_on(listener, fs, clock, out, whole))
    Error(_): Error(Unbound(port: place.port))
  end
end

fn compacted_store(fs: Fs, dir: String, opened: Table) : Result(Table, Problem)
  case compact(fs, opened)
    Ok(table): Ok(table)
    Error(_): Error(Unopened(dir: dir, why: "holds a notes.log notes could not rewrite"))
  end
end

fn compacted(fs: Fs, dir: String, opened: Table) : Result(String, Problem)
  table = try compacted_store(fs, dir, opened)
  Ok("notes: compacted #{dir}/notes.log from #{lines(opened)} lines to #{count(table)}\n")
end

# The service and its acceptor over a store just opened, and every exchange handed to the
# acceptor until notes is stopped; a for needs a range to repeat, so after 100 million
# accepts it returns (GAPS.md).
fn served_on(listener: HttpListener, fs: Fs, clock: Clock, out: Out, table: Table) : String
  service = Service.start(fs, clock, opening(table, clock.now))
  acceptor = Acceptor.start(listener, service)
  out.write_line("notes: serving #{table.dir} on 127.0.0.1:#{listener.port}")
  out.flush
  var taken = 0
  for _ in 0..10_000
    taken += accepted_awhile(acceptor)
  end
  "notes: answered #{taken} requests\n"
end

fn accepted_awhile(acceptor: Handle(Acceptor)) : UInt64
  var taken = 0
  for _ in 0..10_000
    if acceptor.ask(Accept, within: 60_000.ms) is Ok(true)
      taken += 1
    end
  end
  taken
end

fn client(http: Http, trip: Trip) : Result(String, Problem)
  case http.send(request_of(trip), host: trip.host, port: trip.port, within: 10_000.ms)
    Ok(response): Ok(shown(response))
    Error(_): Error(Unreached(host: trip.host, port: trip.port))
  end
end

fn request_of(trip: Trip) : Request
  headers = if trip.token == "-"
    Map.new()
  else
    Map.new().set("authorization", "Bearer #{trip.token}")
  end
  Request(method: trip.method, path: trip.path, headers: headers, body: trip.json)
end

# A response as the client prints it: the status, then the body when there is one.
fn shown(response: Response) : String
  return "#{response.status}\n" if response.body == ""
  "#{response.status} #{response.body}\n"
end

# Serves a folder's log on a free port and plays a script through the client, each line a
# request of its own; the transcript is every line sent and what came back, with times and
# waits that depend on the clock steadied. The folder's log is only read: the changes go to
# notes.check.log beside it, removed before and after.
fn check(http: Http, fs: Fs, clock: Clock, opened: Table, lines: List(String)) : Result(String,
  Problem)
  folder = fs.scoped(opened.dir)
  if !cleared(folder)
    return Error(Unopened(dir: opened.dir, why: "holds a notes.check.log notes cannot remove"))
  end
  case http.listen(0, within: 5_000.ms)
    Ok(listener):
      transcript = checked_on(http, listener, fs, clock, writing_to(opened, "notes.check.log"),
        lines)
      return Ok(transcript) if cleared(folder)
      Error(Unopened(dir: opened.dir, why: "holds a notes.check.log notes cannot remove"))
    Error(_): Error(Unbound(port: 0))
  end
end

fn cleared(folder: Fs) : Bool
  removed = folder.remove("notes.check.log", within: 10_000.ms) is Ok(_)
  removed or folder.size("notes.check.log", within: 10_000.ms) is Error(Missing(_))
end

fn checked_on(http: Http, listener: HttpListener, fs: Fs, clock: Clock, table: Table,
  lines: List(String)) : String
  service = Service.start(fs, clock, opening(table, clock.now))
  acceptor = Acceptor.start(listener, service)
  var transcript = ""
  for line in lines
    acceptor.send(Accept)
    heard = played(http, line, listener.port)
    transcript = "#{transcript}> #{line}\n#{steady(heard)}"
  end
  transcript
end

fn played(http: Http, line: String, port: UInt16) : String
  case trip_of(line.split(" "), "127.0.0.1", port)
    Ok(trip):
      case client(http, trip)
        Ok(text): text
        Error(problem): "#{said(problem)}\n"
      end
    Error(problem): "#{said(problem)}\n"
  end
end

# A transcript with what depends on the clock replaced: each note's times, the service's
# uptime, and a rate-limited client's wait.
fn steady(text: String) : String
  times = masked(masked(text, "created_at", true), "updated_at", true)
  masked(masked(times, "uptime_ms", false), "retry_after_ms", false)
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

# What follows a JSON value at the start of a piece: past the closing quote of a string, or
# from the first , or } after a number.
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

fn script_of(fs: Fs, script: String) : Result(List(String), Problem)
  case fs.read_only.read_lines(script, within: 10_000.ms)
    Ok(lines): Ok(lines)
    Error(Missing(_)): Error(Unopened(dir: script, why: "is not a script notes can read"))
    Error(Timeout): Error(Unopened(dir: script, why: "took longer than 10 seconds to read"))
    Error(NotText): Error(Unopened(dir: script, why: "is not UTF-8 text"))
  end
end

# The folder's store, replayed. A last line cut short is left out and said on stderr, once, at
# once.
fn opened_store(fs: Fs, err: Out, dir: String) : Result(Table, Problem)
  case open(fs, dir)
    Ok(table):
      if cut_short?(table)
        err.write_line("notes: the last line of #{dir}/notes.log was cut short, so it is left out")
        err.flush
      end
      Ok(table)
    Error(problem): Error(Unopened(dir: dir, why: why_unopened(problem)))
  end
end

fn why_unopened(problem: StoreError) : String
  case problem
    NoFolder: "is not a folder notes can read"
    Unreadable: "holds a notes.log notes cannot read"
    Slow: "took longer than ten minutes to read"
    BadLine(number): "holds a notes.log whose line #{number} is not a SET or a DEL"
    Unwritten | Torn: "holds a notes.log notes could not write"
  end
end

fn said(problem: Problem) : String
  case problem
    Usage(detail): "#{detail}; #{usage()}"
    Unopened(dir: dir, why: why): "#{dir} #{why}"
    Unbound(port): "cannot listen on 127.0.0.1:#{port}"
    Unreached(host: host, port: port): "no notes answered at #{host}:#{port}"
  end
end

fn code_of(problem: Problem) : UInt8
  case problem
    Usage(_): 2
    Unopened(dir: _, why: _): 1
    Unbound(_): 1
    Unreached(host: _, port: _): 1
  end
end

fn main(platform: Platform)
  args = platform.args
  case ran(platform.http, platform.fs, platform.clock, platform.stdout, platform.stderr, args)
    Ok(text): platform.stdout.write(text)
    Error(problem):
      platform.stderr.write_line("notes: #{said(problem)}")
      platform.exit(code_of(problem))
  end
end

test "serve takes a folder and an optional port, 7800 by default"
  assert job(["serve", "data"]) == Ok(Serving(place: Place(dir: "data", port: 7_800)))
  assert job(["serve",
    "data",
    "--port",
    "8000"]) == Ok(Serving(place: Place(dir: "data", port: 8_000)))
end

test "a missing folder, a bad port, a short request, or an unknown command is a usage error"
  assert job([]) is Error(Usage(_))
  assert job(["serve"]) is Error(Usage(_))
  assert job(["serve", "--port", "8000"]) is Error(Usage(_))
  assert job(["serve", "data", "--port"]) is Error(Usage(_))
  assert job(["serve", "data", "--port", "0"]) is Error(Usage(_))
  assert job(["serve", "data", "--port", "65536"]) is Error(Usage(_))
  assert job(["compact"]) is Error(Usage(_))
  assert job(["compact", "a", "b"]) is Error(Usage(_))
  assert job(["client", "localhost", "7800", "ada", "GET"]) is Error(Usage(_))
  assert job(["client", "localhost", "port", "ada", "GET", "/notes"]) is Error(Usage(_))
  assert job(["check", "data"]) is Error(Usage(_))
  assert job(["stop"]) is Error(Usage(_))
end

test "client joins the JSON after the path back into one body"
  words = ["client", "localhost", "7800", "ada", "POST", "/notes", "{\"title\":", "\"a b\"}"]
  trip = Trip(host: "localhost", port: 7_800, token: "ada", method: "POST", path: "/notes",
    json: "{\"title\": \"a b\"}")
  assert job(words) == Ok(Asking(trip: trip))
  assert request_of(trip).headers.get("authorization") == Some("Bearer ada")
  var anonymous = trip
  anonymous.token = "-"
  assert request_of(anonymous).headers.size == 0
  assert job(["check", "data", "s.txt"]) == Ok(Checking(dir: "data", script: "s.txt"))
end

test "a response prints as its status and body, and the clock's numbers are steadied"
  assert shown(Response(status: 204, body: "")) == "204\n"
  assert shown(Response(status: 404, body: "{}")) == "404 {}\n"
  note = "{\"id\": \"n_1\", \"created_at\": \"2026-09-13T10:00:00.123Z\", \"updated_at\": \"2026-09-13T10:00:01Z\"}"
  assert steady(note) == "{\"id\": \"n_1\", \"created_at\": \"<created_at>\", \"updated_at\": \"<updated_at>\"}"
  assert steady("{\"notes\": 2, \"clients\": 1, \"uptime_ms\": 1234}") == "{\"notes\": 2, \"clients\": 1, \"uptime_ms\": <uptime_ms>}"
  assert steady("{\"error\": \"rate limited\", \"retry_after_ms\": 59000}") == "{\"error\": \"rate limited\", \"retry_after_ms\": <retry_after_ms>}"
  assert steady("no numbers here") == "no numbers here"
end

test "a store whose last line was cut short opens without it, and says so on the error stream"
  fs = Fs.fixture()
  err = Out.fixture()
  assert fs.write("d/notes.log", "SET a 1\nSET b 2", within: 1_000.ms) is Ok(_)
  assert opened_store(fs, err, "d") is Ok(table)
  assert count(table) == 1
  assert err.written == ["notes: the last line of d/notes.log was cut short, so it is left out\n"]
end

test "a usage error exits 2, and a folder or port that cannot be had exits 1"
  assert code_of(Usage(detail: "x")) == 2
  assert code_of(Unopened(dir: "d", why: "w")) == 1
  assert code_of(Unbound(port: 7_800)) == 1
  assert code_of(Unreached(host: "h", port: 1)) == 1
end

verified: types, contracts, tests (6), property (0 seeds), sim (not run)
          proven: not run
