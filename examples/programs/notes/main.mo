# run: check data/demo data/session.txt
# run: compact data/compact
# run: serve
# exit: 2
# run: serve data/nowhere
# exit: 1
# run: client 127.0.0.1 1 ada GET /notes
# exit: 1
module Notes.Main
expose Job, Place, Trip, Problem, job, steady, serving?, main

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
  # body gone; regenerate
end

fn job(args: List(String)) : Result(Job, Problem)
  # body gone; regenerate
end

fn serving(args: List(String)) : Result(Job, Problem)
  # body gone; regenerate
end

fn compacting(args: List(String)) : Result(Job, Problem)
  # body gone; regenerate
end

fn asking(args: List(String)) : Result(Job, Problem)
  # body gone; regenerate
end

# A token, a method, a path, and any JSON after them, joined by spaces as they were split.
fn trip_of(words: List(String), host: String, port: UInt16) : Result(Trip, Problem)
  # body gone; regenerate
end

fn checking(args: List(String)) : Result(Job, Problem)
  # body gone; regenerate
end

fn dir_of(args: List(String)) : Result(String, Problem)
  # body gone; regenerate
end

fn port_of(text: String) : Result(UInt16, Problem)
  ensures result is Ok(port) implies port >= 1
  # body gone; regenerate
end

fn ran(http: Http, fs: Fs, clock: Clock, out: Out, err: Out, args: List(String)) : Result(String,
  # body gone; regenerate
end

# Serves a folder until notes is stopped. A log whose last line was cut short is compacted
# first, so the next change starts on a line of its own.
fn serve(http: Http, fs: Fs, clock: Clock, out: Out, err: Out, place: Place) : Result(String,
  # body gone; regenerate
end

fn compacted_store(fs: Fs, dir: String, opened: Table) : Result(Table, Problem)
  # body gone; regenerate
end

fn compacted(fs: Fs, dir: String, opened: Table) : Result(String, Problem)
  # body gone; regenerate
end

# The service and its acceptor over a store just opened, and the listener served into the
# acceptor from here on; the runtime owns the loop, so notes serves until it is stopped.
fn served_on(listener: HttpListener, fs: Fs, clock: Clock, out: Out, table: Table) : String
  # body gone; regenerate
end

fn client(http: Http, trip: Trip) : Result(String, Problem)
  # body gone; regenerate
end

fn request_of(trip: Trip) : Request
  # body gone; regenerate
end

# A response as the client prints it: the status, then the body when there is one.
fn shown(response: Response) : String
  # body gone; regenerate
end

# Serves a folder's log on a free port and plays a script through the client, each line a
# request of its own; the transcript is every line sent and what came back, with times and
# waits that depend on the clock steadied. The folder's log is only read: the changes go to
# notes.check.log beside it, removed before and after.
fn check(http: Http, fs: Fs, clock: Clock, opened: Table, lines: List(String)) : Result(String,
  # body gone; regenerate
end

fn cleared(folder: Fs) : Bool
  # body gone; regenerate
end

fn checked_on(http: Http, listener: HttpListener, fs: Fs, clock: Clock, table: Table,
  lines: List(String)) : String
  # body gone; regenerate
end

fn played(http: Http, line: String, port: UInt16) : String
  # body gone; regenerate
end

# A transcript with what depends on the clock replaced: each note's times, the service's
# uptime, and a rate-limited client's wait.
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

# The folder's store, replayed. A last line cut short is left out and said on stderr, once, at
# once.
fn opened_store(fs: Fs, err: Out, dir: String) : Result(Table, Problem)
  # body gone; regenerate
end

fn why_unopened(problem: StoreError) : String
  # body gone; regenerate
end

fn said(problem: Problem) : String
  # body gone; regenerate
end

fn code_of(problem: Problem) : UInt8
  # body gone; regenerate
end

# Whether the arguments say to serve, which goes on until notes is stopped.
fn serving?(args: List(String)) : Bool
  # body gone; regenerate
end

# Serving goes on until notes is stopped; every other command ends notes with exit once it is
# done, since check serves a listener of its own.
fn main(platform: Platform)
  # body gone; regenerate
end

test "serve takes a folder and an optional port, 7800 by default"
  assert job(["serve", "data"]) == Ok(Serving(place: Place(dir: "data", port: 7_800)))
  assert serving?(["serve", "data"])
  assert !serving?(["compact", "data"])
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
