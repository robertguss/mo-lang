# run: check data/demo data/session.txt
# run: compact data/compact
# run: serve
# exit: 2
# run: serve data/nowhere
# exit: 1
# run: client 127.0.0.1 1 p GET /jobs
# exit: 1
# run: verify data/demo
# run: verify data/ill
# exit: 1
module Jobq.Main
expose Place, Trip, Task, Problem, task, steady, serving?, main

use Jobq.Board{health_of, ill_formed, snapshot}
use Jobq.Job{id_of}
use Jobq.Queue{Opening, opening}
use Jobq.Server{serving}
use Jobq.Store{Table, StoreError, count, cut_short?, line_of, lines, open, pairs, rewritten, writing_to}

intent "Run jobq: serve a folder's jobs over HTTP, compact its log to one line per live job in the names this version writes, verify a folder without serving it, send one request as a client, or check a folder by serving it on a free port and playing a script through the client; every command that opens a folder refuses one that holds a record the API could never have produced, a usage error exits 2, and a folder, a port, or a server that cannot be had exits 1."

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

enum Task
  Serving(place: Place)
  Compacting(dir: String)
  Verifying(dir: String)
  Asking(trip: Trip)
  Checking(dir: String, script: String)
end

enum Problem
  Usage(detail: String)
  Unopened(dir: String, why: String)
  Ill(dir: String, key: String, rule: String)
  Unbound(port: UInt16)
  Unreached(host: String, port: UInt16)
end

fn usage() : String
  "usage: jobq serve <dir> [--port N] | jobq compact <dir> | jobq verify <dir> | jobq client <host> <port> <token> <method> <path> [<json>] | jobq check <dir> <script>"
end

fn task(args: List(String)) : Result(Task, Problem)
  rest = args.drop(1)
  case args.first or ""
    "serve": to_serve(rest)
    "compact": compacting(rest)
    "verify": verifying(rest)
    "client": asking(rest)
    "check": checking(rest)
    "": Error(Usage(detail: "no command given"))
    _: Error(Usage(detail: "unknown command #{args.first or ""}"))
  end
end

fn to_serve(args: List(String)) : Result(Task, Problem)
  dir = try dir_of(args)
  flags = args.drop(1)
  return Ok(Serving(place: Place(dir: dir, port: 7_900))) if flags.size == 0
  if flags.size != 2 or flags.first != Some("--port")
    return Error(Usage(detail: "serve takes a folder and then --port N"))
  end
  port = try port_of(flags.get(1) or "")
  Ok(Serving(place: Place(dir: dir, port: port)))
end

fn compacting(args: List(String)) : Result(Task, Problem)
  dir = try dir_of(args)
  return Error(Usage(detail: "compact takes one folder")) if args.size != 1
  Ok(Compacting(dir: dir))
end

fn verifying(args: List(String)) : Result(Task, Problem)
  dir = try dir_of(args)
  return Error(Usage(detail: "verify takes one folder")) if args.size != 1
  Ok(Verifying(dir: dir))
end

fn asking(args: List(String)) : Result(Task, Problem)
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
  Ok(Trip(host: host, port: port, token: words.first or "", method: words.get(1) or "",
    path: words.get(2) or "", json: String.join(words.drop(3), " ")))
end

fn checking(args: List(String)) : Result(Task, Problem)
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
  given = try task(args)
  case given
    Serving(place): serve(http, fs, clock, out, err, place)
    Compacting(dir):
      opened = try opened_store(fs, err, dir)
      compacted(fs, dir, opened, clock.now)
    Verifying(dir):
      opened = try opened_store(fs.read_only, err, dir)
      counted(opened, clock.now)
    Asking(trip): client(http, trip)
    Checking(dir: dir, script: script):
      lines = try script_of(fs, script)
      opened = try opened_store(fs.read_only, err, dir)
      check(http, fs, clock, opened, lines)
  end
end

# Serves a folder until jobq is stopped. A log whose last line was cut short is written whole
# first, so the next change starts on a line of its own.
fn serve(http: Http, fs: Fs, clock: Clock, out: Out, err: Out, place: Place) : Result(String,
  Problem)
  opened = try opened_store(fs, err, place.dir)
  start = try opening_of(opened, clock.now)
  whole = if cut_short?(opened): try compacted_from(fs, place.dir, start) else: start
  case http.listen(place.port, within: 5_000.ms)
    Ok(listener):
      queue = serving(listener, fs, clock, whole)
      queue.send(Sweep)
      out.write_line("jobq: serving #{place.dir} on 127.0.0.1:#{listener.port}")
      out.flush
      Ok("")
    Error(_): Error(Unbound(port: place.port))
  end
end

fn opening_of(table: Table, now: Time) : Result(Opening, Problem)
  case opening(table, now)
    Some(start): Ok(start)
    None: Error(Unopened(dir: table.dir, why: "holds a jobq.log with a record that is not a job"))
  end
end

# The log written whole from the board the store replayed: one line per live job, in the names
# this version writes, so a log the previous version wrote leaves no old name behind.
fn compacted_from(fs: Fs, dir: String, start: Opening) : Result(Opening, Problem)
  case rewritten(fs, start.table, snapshot(start.board).map(fn(w) line_of(w) end))
    Ok(table): Ok(Opening(board: start.board, table: table))
    Error(_): Error(Unopened(dir: dir, why: "holds a jobq.log jobq could not rewrite"))
  end
end

fn compacted(fs: Fs, dir: String, opened: Table, now: Time) : Result(String, Problem)
  start = try opening_of(opened, now)
  whole = try compacted_from(fs, dir, start)
  Ok("jobq: compacted #{dir}/jobq.log from #{lines(opened)} lines to #{lines(whole.table)}\n")
end

# What a folder holds once it opens, for an operator who wants to know before serving it: its
# jobs by state and the id the next create would take.
fn counted(opened: Table, now: Time) : Result(String, Problem)
  start = try opening_of(opened, now)
  counts = health_of(start.board, now)
  jobs = counts.queued + counts.scheduled + counts.leased + counts.done + counts.dead
  states = "queued #{counts.queued}, scheduled #{counts.scheduled}, leased #{counts.leased}"
  ended = "done #{counts.done}, dead #{counts.dead}"
  Ok("#{jobs} jobs: #{states}, #{ended}; next id #{id_of(start.board.next)}\n")
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
  Request(method: trip.method, path: path_of(trip.path), query: query_of(trip.path),
    headers: headers, body: trip.json)
end

# The path before a ?, and the query after it split into its pairs, as the client writes them.
fn path_of(target: String) : String
  target.slice(0, target.index_of("?") or target.size)
end

fn query_of(target: String) : Map(String, String)
  at = target.index_of("?") or target.size
  pairs = target.slice(at + 1, target.size).split("&").filter(fn(pair) pair != "" end)
  pairs.reduce(Map.new(), fn(query, pair)
    query.set(pair.slice(0, pair.index_of("=") or pair.size),
      pair.slice((pair.index_of("=") or pair.size) + 1, pair.size))
  end)
end

# A response as the client prints it: the status, then the body when there is one.
fn shown(response: Response) : String
  return "#{response.status}\n" if response.body == ""
  "#{response.status} #{response.body}\n"
end

# Serves a folder's jobs on a free port and plays a script through the client, each line a
# request of its own; the transcript is every line sent and what came back, with the times the
# clock gives steadied. The folder's log is only read: the changes go to jobq.check.log beside
# it, removed before and after.
fn check(http: Http, fs: Fs, clock: Clock, opened: Table, lines: List(String)) : Result(String,
  Problem)
  folder = fs.scoped(opened.dir)
  if !cleared(folder)
    return Error(Unopened(dir: opened.dir, why: "holds a jobq.check.log jobq cannot remove"))
  end
  start = try opening_of(writing_to(opened, "jobq.check.log"), clock.now)
  case http.listen(0, within: 5_000.ms)
    Ok(listener):
      transcript = checked_on(http, listener, fs, clock, start, lines)
      return Ok(transcript) if cleared(folder)
      Error(Unopened(dir: opened.dir, why: "holds a jobq.check.log jobq cannot remove"))
    Error(_): Error(Unbound(port: 0))
  end
end

fn cleared(folder: Fs) : Bool
  removed = folder.remove("jobq.check.log", within: 10_000.ms) is Ok(_)
  removed or folder.size("jobq.check.log", within: 10_000.ms) is Error(Missing(_))
end

fn checked_on(http: Http, listener: HttpListener, fs: Fs, clock: Clock, start: Opening,
  lines: List(String)) : String
  queue = serving(listener, fs, clock, start)
  queue.send(Sweep)
  var transcript = ""
  for line in lines
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

# A transcript with what depends on the clock replaced: each job's times, the time it runs at,
# and the uptime.
fn steady(text: String) : String
  times = masked(masked(text, "created_at", true), "updated_at", true)
  waits = masked(times, "run_at", true)
  masked(masked(waits, "lease_until", true), "uptime_ms", false)
end

fn masked(text: String, key: String, quoted: Bool) : String
  label = "\"#{key}\": "
  pieces = text.split(label)
  mark = if quoted: "\"<#{key}>\"" else: "<#{key}>"
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
    Error(Missing(_)): Error(Unopened(dir: script, why: "is not a script jobq can read"))
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
        err.write_line("jobq: the last line of #{dir}/jobq.log was cut short, so it is left out")
        err.flush
      end
      whole(table)
    Error(problem): Error(Unopened(dir: dir, why: why_unopened(problem)))
  end
end

# Every record checked against the job's rules before anything is served, compacted, or
# verified: the first that breaks one refuses the folder, naming the record and the rule.
fn whole(table: Table) : Result(Table, Problem)
  case ill_formed(pairs(table))
    Some(bad): Error(Ill(dir: table.dir, key: bad.0, rule: bad.1))
    None: Ok(table)
  end
end

fn why_unopened(problem: StoreError) : String
  case problem
    NoFolder: "is not a folder jobq can read"
    Unreadable: "holds a jobq.log jobq cannot read"
    Slow: "took longer than ten minutes to read"
    BadLine(number): "holds a jobq.log whose line #{number} is not a SET or a DEL"
    Unwritten | Torn: "holds a jobq.log jobq could not write"
  end
end

fn said(problem: Problem) : String
  case problem
    Usage(detail): "#{detail}; #{usage()}"
    Unopened(dir: dir, why: why): "#{dir} #{why}"
    Ill(dir: dir, key: key, rule: rule): "#{dir}: record #{key}: #{rule}"
    Unbound(port): "cannot listen on 127.0.0.1:#{port}"
    Unreached(host: host, port: port): "no jobq answered at #{host}:#{port}"
  end
end

fn code_of(problem: Problem) : UInt8
  case problem
    Usage(_): 2
    Unopened(dir: _, why: _): 1
    Ill(dir: _, key: _, rule: _): 1
    Unbound(_): 1
    Unreached(host: _, port: _): 1
  end
end

# Whether the arguments say to serve, which goes on until jobq is stopped.
fn serving?(args: List(String)) : Bool
  task(args) is Ok(Serving(_))
end

# Serving goes on until jobq is stopped; every other command ends jobq with exit once it is done,
# since check serves a listener of its own.
fn main(platform: Platform)
  args = platform.args
  case ran(platform.http, platform.fs, platform.clock, platform.stdout, platform.stderr, args)
    Ok(text):
      platform.stdout.write(text)
      if !serving?(args)
        platform.exit(0)
      end
    Error(problem):
      platform.stderr.write_line("jobq: #{said(problem)}")
      platform.exit(code_of(problem))
  end
end

# A record as the previous version wrote it, with attempts and max_attempts and no backoff.
fn old_record(id: String, state: String, attempts: UInt64) : String
  "{\"id\": \"#{id}\", \"queue\": \"emails\", \"state\": \"#{state}\", \"payload\": \"p\", \"attempts\": #{attempts}, \"max_attempts\": 3, \"created_at\": \"2026-09-14T09:00:00Z\", \"updated_at\": \"2026-09-14T09:05:00Z\"}"
end

test "serve takes a folder and an optional port, 7900 by default"
  assert task(["serve", "data"]) == Ok(Serving(place: Place(dir: "data", port: 7_900)))
  assert serving?(["serve", "data"])
  assert !serving?(["compact", "data"])
  assert task(["serve",
    "data",
    "--port",
    "8000"]) == Ok(Serving(place: Place(dir: "data", port: 8_000)))
end

test "a missing folder, a bad port, a short request, or an unknown command is a usage error"
  assert task([]) is Error(Usage(_))
  assert task(["serve"]) is Error(Usage(_))
  assert task(["serve", "--port", "8000"]) is Error(Usage(_))
  assert task(["serve", "data", "--port"]) is Error(Usage(_))
  assert task(["serve", "data", "--port", "0"]) is Error(Usage(_))
  assert task(["serve", "data", "--port", "65536"]) is Error(Usage(_))
  assert task(["compact"]) is Error(Usage(_))
  assert task(["compact", "a", "b"]) is Error(Usage(_))
  assert task(["client", "localhost", "7900", "p", "GET"]) is Error(Usage(_))
  assert task(["client", "localhost", "port", "p", "GET", "/jobs"]) is Error(Usage(_))
  assert task(["check", "data"]) is Error(Usage(_))
  assert task(["stop"]) is Error(Usage(_))
end

test "client joins the JSON after the path back into one body, and splits a query from the path"
  words = ["client", "localhost", "7900", "p", "POST", "/jobs", "{\"queue\":", "\"a\"}"]
  trip = Trip(host: "localhost", port: 7_900, token: "p", method: "POST", path: "/jobs",
    json: "{\"queue\": \"a\"}")
  assert task(words) == Ok(Asking(trip: trip))
  assert request_of(trip).headers.get("authorization") == Some("Bearer p")
  var anonymous = trip
  anonymous.token = "-"
  anonymous.path = "/jobs?queue=emails&state=scheduled"
  listing = request_of(anonymous)
  assert listing.headers.size == 0 and listing.path == "/jobs"
  assert listing.query == Map.new().set("queue", "emails").set("state", "scheduled")
  assert task(["check", "data", "s.txt"]) == Ok(Checking(dir: "data", script: "s.txt"))
end

test "a response prints as its status and body, and the clock's numbers are steadied"
  assert shown(Response(status: 204, body: "")) == "204\n"
  assert shown(Response(status: 404, body: "{}")) == "404 {}\n"
  job = "{\"id\": \"j_1\", \"created_at\": \"2026-09-14T10:00:00.123Z\", \"updated_at\": \"2026-09-14T10:00:01Z\", \"worker\": \"w\", \"lease_until\": \"2026-09-14T10:00:31Z\"}"
  assert steady(job) == "{\"id\": \"j_1\", \"created_at\": \"<created_at>\", \"updated_at\": \"<updated_at>\", \"worker\": \"w\", \"lease_until\": \"<lease_until>\"}"
  later = "{\"id\": \"j_2\", \"state\": \"scheduled\", \"updated_at\": \"2026-09-14T10:00:01Z\", \"run_at\": \"2026-09-14T11:00:01Z\"}"
  assert steady(later) == "{\"id\": \"j_2\", \"state\": \"scheduled\", \"updated_at\": \"<updated_at>\", \"run_at\": \"<run_at>\"}"
  assert steady("{\"queued\": 1, \"dead\": 0, \"uptime_ms\": 1234}") == "{\"queued\": 1, \"dead\": 0, \"uptime_ms\": <uptime_ms>}"
  assert steady("no numbers here") == "no numbers here"
end

test "a store whose last line was cut short opens without it, and says so on the error stream"
  fs = Fs.fixture()
  err = Out.fixture()
  cut = "SET j_1 #{old_record("j_1", "queued", 0)}\nSET j_2 {\"id\": \"j_2\""
  assert fs.write("d/jobq.log", cut, within: 1_000.ms) is Ok(_)
  assert opened_store(fs, err, "d") is Ok(table)
  assert count(table) == 1
  assert err.written == ["jobq: the last line of d/jobq.log was cut short, so it is left out\n"]
  assert opening_of(table, Time.fixture()) is Ok(_)
end

# The incident's first lesson: a record in a state the API can never produce refuses the folder
# at the door, whichever command opened it, and names the record and the rule it breaks.
test "a folder with a record no request could have left is refused, and a whole one is verified"
  fs = Fs.fixture()
  err = Out.fixture()
  good = "SET ids 1000\nSET j_1 #{old_record("j_1", "queued", 0)}\nSET j_2 #{old_record("j_2", "done", 1)}\n"
  assert fs.write("d/jobq.log", good, within: 1.minute) is Ok(_)
  assert opened_store(fs, err, "d") is Ok(table)
  assert counted(table, Time.fixture()) == Ok("2 jobs: queued 1, scheduled 0, leased 0, done 1, dead 0; next id j_1000\n")
  ill = good.replace("\"state\": \"done\", \"payload\": \"p\", \"attempts\": 1",
    "\"state\": \"done\", \"payload\": \"p\", \"attempts\": 0")
  assert fs.write("d/jobq.log", ill, within: 1.minute) is Ok(_)
  assert opened_store(fs, err, "d") == Error(Ill(dir: "d", key: "j_2",
    rule: "a done job has at least one try"))
  named = good.replace("SET j_2 {\"id\": \"j_2\"", "SET j_7 {\"id\": \"j_2\"")
  assert fs.write("d/jobq.log", named, within: 1.minute) is Ok(_)
  assert opened_store(fs, err, "d") == Error(Ill(dir: "d", key: "j_7",
    rule: "its id is j_2, not its key"))
  assert fs.write("d/jobq.log", good.replace("SET ids 1000", "SET ids nine"), within: 1.minute) is Ok(_)
  assert opened_store(fs, err, "d") == Error(Ill(dir: "d", key: "ids", rule: "is not a number"))
  assert said(Ill(dir: "d", key: "j_2", rule: "is not a job")) == "d: record j_2: is not a job"
  assert code_of(Ill(dir: "d", key: "j_2", rule: "is not a job")) == 1
end

test "a log the previous version wrote compacts to one line per job, and no old name is left"
  fs = Fs.fixture()
  err = Out.fixture()
  old = "SET ids 1000\nSET j_1 #{old_record("j_1", "queued", 0)}\nSET j_2 #{old_record("j_2", "done", 1)}\n"
  assert fs.write("d/jobq.log", old, within: 1.minute) is Ok(_)
  assert opened_store(fs, err, "d") is Ok(table)
  assert lines(table) == 3 and count(table) == 3
  assert compacted(fs, "d", table, Time.fixture()) == Ok("jobq: compacted d/jobq.log from 3 lines to 3\n")
  assert fs.read("d/jobq.log", within: 1.minute) is Ok(text)
  assert !text.contains?("attempts")
  assert text.contains?("\"tries\": 0, \"max_tries\": 3, \"backoff_ms\": 0")
  assert text.contains?("\"tries\": 1, \"max_tries\": 3, \"backoff_ms\": 0")
  assert opened_store(fs, err, "d") is Ok(again)
  assert count(again) == 3 and lines(again) == 3
  assert opening_of(again, Time.fixture()) is Ok(_)
end

test "verify takes one folder, and names the folder it cannot open"
  assert task(["verify", "data"]) == Ok(Verifying(dir: "data"))
  assert task(["verify"]) is Error(Usage(_))
  assert task(["verify", "a", "b"]) is Error(Usage(_))
  assert task(["verify", "--port"]) is Error(Usage(_))
  assert !serving?(["verify", "data"])
  fs = Fs.fixture()
  err = Out.fixture()
  assert opened_store(fs, err, "nowhere") is Error(Unopened(dir: "nowhere", why: _))
  assert fs.mkdir("d", within: 1.minute) is Ok(_)
  assert opened_store(fs, err, "d") is Ok(empty)
  assert counted(empty, Time.fixture()) == Ok("0 jobs: queued 0, scheduled 0, leased 0, done 0, dead 0; next id j_1\n")
end

test "a usage error exits 2, and a folder, a port, or a server that cannot be had exits 1"
  assert code_of(Usage(detail: "x")) == 2
  assert code_of(Unopened(dir: "d", why: "w")) == 1
  assert code_of(Unbound(port: 7_900)) == 1
  assert code_of(Unreached(host: "h", port: 1)) == 1
end

verified: types, contracts, tests (9), property (0 seeds), sim (not run)
          proven: not run
