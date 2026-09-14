# run: check data/demo data/session.txt
# run: compact data/compact
# run: serve
# exit: 2
# run: serve data/nowhere
# exit: 1
# run: client 127.0.0.1 1 ada GET /jobs
# exit: 1
module Jobq.Main
expose Task, Spot, Trip, Script, Problem, task, steady, serving?, main

use Jobq.Books{Place}
use Jobq.Queue{Opened, Service}
use Jobq.Server{Acceptor}
use Jobq.Store{Table, open, compact, cut_short?, lines, count}

intent "Run jobq: serve a folder's jobs over HTTP, compact its log to one line per live key, send one request as a client, or check a folder by serving it on a free port and playing a script through the client; a usage error exits 2, and a folder or port that cannot be had exits 1."

# Where to serve: the folder and the port.
struct Spot
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

# A folder to check, and the lines of the script played against it.
struct Script
  dir: String
  lines: List(String)
end

enum Task
  Serving(spot: Spot)
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
  "usage: jobq serve <dir> [--port N] | jobq compact <dir> | jobq client <host> <port> <token> <method> <path> [<json>] | jobq check <dir> <script>"
end

fn task(args: List(String)) : Result(Task, Problem)
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

fn serving(args: List(String)) : Result(Task, Problem)
  dir = try dir_of(args)
  flags = args.drop(1)
  return Ok(Serving(spot: Spot(dir: dir, port: 7_900))) if flags.size == 0
  if flags.size != 2 or flags.first != Some("--port")
    return Error(Usage(detail: "serve takes a folder and then --port N"))
  end
  port = try port_of(flags.get(1) or "")
  Ok(Serving(spot: Spot(dir: dir, port: port)))
end

fn compacting(args: List(String)) : Result(Task, Problem)
  dir = try dir_of(args)
  return Error(Usage(detail: "compact takes one folder")) if args.size != 1
  Ok(Compacting(dir: dir))
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
  json = String.join(words.drop(3), " ")
  Ok(Trip(host: host, port: port, token: words.first or "", method: words.get(1) or "",
    path: words.get(2) or "", json: json))
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

fn ran(http: Http, net: Net, fs: Fs, clock: Clock, err: Out, args: List(String)) : Result(String,
  Problem)
  given = try task(args)
  case given
    Serving(spot): serve(http, fs, clock, err, spot)
    Compacting(dir): compacted(fs, err, dir)
    Asking(trip): client(http, trip)
    Checking(dir: dir, script: script):
      played_script = Script(dir: dir, lines: try script_of(fs, script))
      return Error(Unopened(dir: dir,
        why: "holds a jobq.check.log jobq cannot remove")) if !cleared(fs.scoped(dir))
      service = try opened_service(fs, clock, err, Place(dir: dir, log: "jobq.check.log"))
      check(http, net, fs, err, service, played_script)
  end
end

# The service over the folder, opened before the listener is served, so a folder that cannot
# be read exits 1 and a log of any size is replayed before the first request. The ask waits 21
# minutes, the store's deadlines for two logs added up (check replays its own after the
# folder's): 10 minutes for each log's lines and 20 seconds for its folder and size.
fn opened_service(fs: Fs, clock: Clock, err: Out, place: Place) : Result(Handle(Service), Problem)
  service = Service.start(fs, clock, place, clock.now)
  case service.ask(Open, within: 1_260_000.ms)
    Ok(Ready(jobs: _, cut: cut)):
      if cut
        err.write_line("jobq: the last line of #{place.dir}/jobq.log was cut short, so it is left out")
        err.flush
      end
      Ok(service)
    Ok(Unready(why)): Error(Unopened(dir: place.dir, why: why))
    Error(_): Error(Unopened(dir: place.dir, why: "took longer than 21 minutes to open"))
  end
end

# Serves a folder until jobq is stopped; the runtime owns the loop. A request not whole within 5
# seconds of its connection is closed, which with the acceptor's mailbox of 4,096 is what keeps a
# crowd of silent connections from holding up the rest.
fn serve(http: Http, fs: Fs, clock: Clock, err: Out, spot: Spot) : Result(String, Problem)
  service = try opened_service(fs, clock, err, Place(dir: spot.dir, log: "jobq.log"))
  case http.listen(spot.port, within: 5_000.ms)
    Ok(listener):
      listener.serve(into: Acceptor.start(service), idle: 5_000.ms)
      Ok("jobq: serving #{spot.dir} on 127.0.0.1:#{listener.port}\n")
    Error(_): Error(Unbound(port: spot.port))
  end
end

fn compacted(fs: Fs, err: Out, dir: String) : Result(String, Problem)
  case open(fs, dir)
    Ok(table):
      if cut_short?(table)
        err.write_line("jobq: the last line of #{dir}/jobq.log was cut short, so it is left out")
      end
      whole = try compacted_table(fs, dir, table)
      Ok("jobq: compacted #{dir}/jobq.log from #{lines(table)} lines to #{count(whole)}\n")
    Error(_): Error(Unopened(dir: dir, why: "is not a folder with a jobq.log jobq can read"))
  end
end

fn compacted_table(fs: Fs, dir: String, table: Table) : Result(Table, Problem)
  case compact(fs, table)
    Ok(whole): Ok(whole)
    Error(_): Error(Unopened(dir: dir, why: "holds a jobq.log jobq could not rewrite"))
  end
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
  Request(method: trip.method, path: bare(trip.path), query: query_of(trip.path), headers: headers,
    body: trip.json)
end

# The query a path's ? starts, as key=value pairs split at &; the client sends the path before
# the ? and the query as the request's query, so the runtime writes them back as they were.
fn query_of(path: String) : Map(String, String)
  at = path.index_of("?") or path.size
  pairs = path.slice(at + 1, path.size).split("&").filter(fn(p) p != "" end)
  pairs.reduce(Map.new(), fn(query, pair) with_pair(query, pair) end)
end

fn with_pair(query: Map(String, String), pair: String) : Map(String, String)
  at = pair.index_of("=") or pair.size
  query.set(pair.slice(0, at), pair.slice(at + 1, pair.size))
end

# The path a request line names, without its query.
fn bare(path: String) : String
  path.slice(0, path.index_of("?") or path.size)
end

# A response as the client prints it: the status, then the body when there is one.
fn shown(response: Response) : String
  return "#{response.status}\n" if response.body == ""
  "#{response.status} #{response.body}\n"
end

# Serves a folder's jobs on a free port, their changes going to jobq.check.log beside its
# jobq.log, removed before the service opened and after the script, and plays the script
# through the client.
fn check(http: Http, net: Net, fs: Fs, err: Out, service: Handle(Service),
  script: Script) : Result(String, Problem)
  case http.listen(0, within: 5_000.ms)
    Ok(listener):
      listener.serve(into: Acceptor.start(service), idle: 5_000.ms)
      transcript = played(http, net, err, listener.port, script.lines)
      return Ok(transcript) if cleared(fs.scoped(script.dir))
      Error(Unopened(dir: script.dir, why: "holds a jobq.check.log jobq cannot remove"))
    Error(_): Error(Unbound(port: 0))
  end
end

fn cleared(folder: Fs) : Bool
  removed = folder.remove("jobq.check.log", within: 10_000.ms) is Ok(_)
  removed or folder.size("jobq.check.log", within: 10_000.ms) is Error(Missing(_))
end

# Each line of the script sent as a request of its own, and what came back, with the clock's
# numbers steadied. A line `crowd N` opens N connections that send nothing, held until the script
# ends; how many opened goes to stderr, since the system's descriptor limit decides it.
fn played(http: Http, net: Net, err: Out, port: UInt16, script: List(String)) : String
  var crowd = []
  var transcript = ""
  for line in script
    wanted = crowd_of(line)
    for _ in 0..wanted
      case net.connect("127.0.0.1", port, within: 1_000.ms)
        Ok(conn):
          crowd = crowd.push(conn)
        Error(_):
          break
      end
    end
    if wanted > 0
      err.write_line("jobq: holding #{crowd.size} of #{wanted} connections that send nothing")
    end
    transcript = "#{transcript}> #{line}\n#{heard(http, line, port, wanted)}"
  end
  transcript
end

fn crowd_of(line: String) : UInt64
  return 0 if !line.starts_with?("crowd ")
  line.slice(6, line.size).to_u64 or 0
end

fn heard(http: Http, line: String, port: UInt16, crowd: UInt64) : String
  return "the connections stay open, sending nothing, until the script ends\n" if crowd > 0
  case trip_of(line.split(" "), "127.0.0.1", port)
    Ok(trip):
      case client(http, trip)
        Ok(text): steady(text)
        Error(problem): "#{said(problem)}\n"
      end
    Error(problem): "#{said(problem)}\n"
  end
end

# A transcript with what depends on the clock replaced: a job's times and the service's uptime.
fn steady(text: String) : String
  times = masked(masked(text, "created_at", true), "updated_at", true)
  masked(masked(times, "lease_until", true), "uptime_ms", false)
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
    Ok(script_lines): Ok(script_lines)
    Error(Missing(_)): Error(Unopened(dir: script, why: "is not a script jobq can read"))
    Error(Timeout): Error(Unopened(dir: script, why: "took longer than 10 seconds to read"))
    Error(NotText): Error(Unopened(dir: script, why: "is not UTF-8 text"))
  end
end

fn said(problem: Problem) : String
  case problem
    Usage(detail): "#{detail}; #{usage()}"
    Unopened(dir: dir, why: why): "#{dir} #{why}"
    Unbound(port): "cannot listen on 127.0.0.1:#{port}"
    Unreached(host: host, port: port): "no jobq answered at #{host}:#{port}"
  end
end

fn code_of(problem: Problem) : UInt8
  case problem
    Usage(_): 2
    Unopened(dir: _, why: _) | Unbound(_) | Unreached(host: _, port: _): 1
  end
end

# Whether the arguments say to serve, which goes on until jobq is stopped.
fn serving?(args: List(String)) : Bool
  task(args) is Ok(Serving(_))
end

# Serving goes on until jobq is stopped; every other command ends jobq with exit once it is
# done, since check serves a listener of its own.
fn main(platform: Platform)
  args = platform.args
  case ran(platform.http, platform.net, platform.fs, platform.clock, platform.stderr, args)
    Ok(text):
      platform.stdout.write(text)
      platform.stdout.flush
      if !serving?(args)
        platform.exit(0)
      end
    Error(problem):
      platform.stderr.write_line("jobq: #{said(problem)}")
      platform.exit(code_of(problem))
  end
end

test "serve takes a folder and an optional port, 7900 by default"
  assert task(["serve", "data"]) == Ok(Serving(spot: Spot(dir: "data", port: 7_900)))
  assert serving?(["serve", "data"]) and !serving?(["compact", "data"])
  assert task(["serve",
    "data",
    "--port",
    "8000"]) == Ok(Serving(spot: Spot(dir: "data", port: 8_000)))
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
  assert task(["client", "localhost", "7900", "ada", "GET"]) is Error(Usage(_))
  assert task(["client", "localhost", "port", "ada", "GET", "/jobs"]) is Error(Usage(_))
  assert task(["check", "data"]) is Error(Usage(_))
  assert task(["stop"]) is Error(Usage(_))
end

test "client joins the JSON after the path into one body, and sends a path's query as a query"
  words = ["client", "localhost", "7900", "ada", "POST", "/jobs", "{\"queue\":", "\"q\"}"]
  trip = Trip(host: "localhost", port: 7_900, token: "ada", method: "POST", path: "/jobs",
    json: "{\"queue\": \"q\"}")
  assert task(words) == Ok(Asking(trip: trip))
  assert request_of(trip).headers.get("authorization") == Some("Bearer ada")
  var listing = trip
  listing.path = "/jobs?state=dead"
  assert request_of(listing).path == "/jobs" and request_of(listing).query.get("state") == Some("dead")
  var anonymous = trip
  anonymous.token = "-"
  assert request_of(anonymous).headers.size == 0
  assert query_of("/jobs?queue=emails&state=dead") == Map.new().set("queue", "emails").set("state",
    "dead")
  assert query_of("/jobs").size == 0 and bare("/jobs?state=done") == "/jobs"
  assert crowd_of("crowd 1200") == 1_200 and crowd_of("ada GET /jobs") == 0
end

test "a response prints as its status and body, and the clock's numbers are steadied"
  assert shown(Response(status: 204, body: "")) == "204\n"
  job = "{\"id\": \"j_1\", \"created_at\": \"2026-09-13T10:00:00.123Z\", \"updated_at\": \"x\", \"worker\": \"w\", \"lease_until\": \"y\"}"
  assert steady(job) == "{\"id\": \"j_1\", \"created_at\": \"<created_at>\", \"updated_at\": \"<updated_at>\", \"worker\": \"w\", \"lease_until\": \"<lease_until>\"}"
  assert steady("{\"dead\": 0, \"uptime_ms\": 1234}") == "{\"dead\": 0, \"uptime_ms\": <uptime_ms>}"
  assert steady("no numbers here") == "no numbers here"
end

test "a usage error exits 2, and a folder or port that cannot be had exits 1"
  assert code_of(Usage(detail: "x")) == 2
  assert code_of(Unopened(dir: "d", why: "w")) == 1
  assert code_of(Unbound(port: 7_900)) == 1
  assert code_of(Unreached(host: "h", port: 1)) == 1
end

verified: types, contracts, tests (5), property (0 seeds), sim (not run)
          proven: not run
