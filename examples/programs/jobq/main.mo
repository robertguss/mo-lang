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
  # body gone; regenerate
end

fn task(args: List(String)) : Result(Task, Problem)
  # body gone; regenerate
end

fn serving(args: List(String)) : Result(Task, Problem)
  # body gone; regenerate
end

fn compacting(args: List(String)) : Result(Task, Problem)
  # body gone; regenerate
end

fn asking(args: List(String)) : Result(Task, Problem)
  # body gone; regenerate
end

# A token, a method, a path, and any JSON after them, joined by spaces as they were split.
fn trip_of(words: List(String), host: String, port: UInt16) : Result(Trip, Problem)
  # body gone; regenerate
end

fn checking(args: List(String)) : Result(Task, Problem)
  # body gone; regenerate
end

fn dir_of(args: List(String)) : Result(String, Problem)
  # body gone; regenerate
end

fn port_of(text: String) : Result(UInt16, Problem)
  ensures result is Ok(port) implies port >= 1
  # body gone; regenerate
end

fn ran(http: Http, net: Net, fs: Fs, clock: Clock, err: Out, args: List(String)) : Result(String,
  # body gone; regenerate
end

# The service over the folder, opened before the listener is served, so a folder that cannot
# be read exits 1 and a log of any size is replayed before the first request. The ask waits 21
# minutes, and the replay of both logs (check replays its own after the folder's) runs on what
# remains of them.
fn opened_service(fs: Fs, clock: Clock, err: Out, place: Place) : Result(Handle(Service), Problem)
  # body gone; regenerate
end

# Serves a folder until jobq is stopped; the runtime owns the loop. A request not whole within 5
# seconds of its connection is closed, which with the acceptor's mailbox of 4,096 is what keeps a
# crowd of silent connections from holding up the rest.
fn serve(http: Http, fs: Fs, clock: Clock, err: Out, spot: Spot) : Result(String, Problem)
  # body gone; regenerate
end

fn compacted(fs: Fs, err: Out, dir: String) : Result(String, Problem)
  # body gone; regenerate
end

fn compacted_table(fs: Fs, dir: String, table: Table) : Result(Table, Problem)
  # body gone; regenerate
end

fn client(http: Http, trip: Trip) : Result(String, Problem)
  # body gone; regenerate
end

fn request_of(trip: Trip) : Request
  # body gone; regenerate
end

# The query a path's ? starts, as key=value pairs split at &; the client sends the path before
# the ? and the query as the request's query, so the runtime writes them back as they were.
fn query_of(path: String) : Map(String, String)
  # body gone; regenerate
end

fn with_pair(query: Map(String, String), pair: String) : Map(String, String)
  # body gone; regenerate
end

# The path a request line names, without its query.
fn bare(path: String) : String
  # body gone; regenerate
end

# A response as the client prints it: the status, then the body when there is one.
fn shown(response: Response) : String
  # body gone; regenerate
end

# Serves a folder's jobs on a free port, their changes going to jobq.check.log beside its
# jobq.log, removed before the service opened and after the script, and plays the script
# through the client.
fn check(http: Http, net: Net, fs: Fs, err: Out, service: Handle(Service),
  script: Script) : Result(String, Problem)
  # body gone; regenerate
end

fn cleared(folder: Fs) : Bool
  # body gone; regenerate
end

# Each line of the script sent as a request of its own, and what came back, with the clock's
# numbers steadied. A line `crowd N` opens N connections that send nothing, held until the script
# ends; how many opened goes to stderr, since the system's descriptor limit decides it.
fn played(http: Http, net: Net, err: Out, port: UInt16, script: List(String)) : String
  # body gone; regenerate
end

fn crowd_of(line: String) : UInt64
  # body gone; regenerate
end

fn heard(http: Http, line: String, port: UInt16, crowd: UInt64) : String
  # body gone; regenerate
end

# A transcript with what depends on the clock replaced: a job's times and the service's uptime.
fn steady(text: String) : String
  # body gone; regenerate
end

fn masked(text: String, key: String, quoted: Bool) : String
  # body gone; regenerate
end

# What follows a JSON value at the start of a piece: past the closing quote of a string, or
# from the first , or } after a number.
fn after_value(piece: String, quoted: Bool) : String
  # body gone; regenerate
end

fn found(at: Option(UInt64)) : List(UInt64)
  # body gone; regenerate
end

fn script_of(fs: Fs, script: String) : Result(List(String), Problem)
  # body gone; regenerate
end

fn said(problem: Problem) : String
  # body gone; regenerate
end

fn code_of(problem: Problem) : UInt8
  # body gone; regenerate
end

# Whether the arguments say to serve, which goes on until jobq is stopped.
fn serving?(args: List(String)) : Bool
  # body gone; regenerate
end

# Serving goes on until jobq is stopped; every other command ends jobq with exit once it is
# done, since check serves a listener of its own.
fn main(platform: Platform)
  # body gone; regenerate
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
