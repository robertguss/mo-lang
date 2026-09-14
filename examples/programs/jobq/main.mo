# run: check data/demo data/session.txt
# run: compact data/compact
# run: serve
# exit: 2
# run: serve data/nowhere
# exit: 1
# run: client 127.0.0.1 1 ada GET /jobs
# exit: 1
module Jobq.Main
expose Place, Task, Problem, task, serving?, main

use Jobq.Check{check}
use Jobq.Client{Trip, trip_of, asked}
use Jobq.Queue{Queue, opening}
use Jobq.Server{Acceptor}
use Jobq.Store{Table, StoreError, open, compact, cut_short?, lines, count}

intent "Run jobq: serve a folder's jobs over HTTP, compact its log to one line per live job, send one request as a client, or check a folder by serving it on a free port and playing a script through the client; a usage error exits 2, and a folder, a port, or a server that cannot be had exits 1."

struct Place
  dir: String
  port: UInt16
end

enum Task
  Serving(place: Place)
  Compacting(dir: String)
  Asking(trip: Trip)
  Checking(dir: String, script: String)
end

enum Problem
  Usage(detail: String)
  Unopened(dir: String, why: String)
  Unbound(port: UInt16)
  Unreached(why: String)
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

fn asking(args: List(String)) : Result(Task, Problem)
  if args.size < 5
    return Error(Usage(detail: "client takes a host, a port, a token, a method, and a path"))
  end
  port = try port_of(args.get(1) or "")
  case trip_of(args.drop(2), args.first or "", port)
    Ok(trip): Ok(Asking(trip: trip))
    Error(why): Error(Usage(detail: why))
  end
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
    Serving(place): serve(http, fs, clock, err, place)
    Compacting(dir):
      opened = try opened_store(fs, err, dir)
      compacted(fs, dir, opened)
    Asking(trip):
      case asked(http, trip)
        Ok(text): Ok(text)
        Error(why): Error(Unreached(why: why))
      end
    Checking(dir: dir, script: script):
      lines = try script_of(fs, script)
      opened = try opened_store(fs.read_only, err, dir)
      case check(http, net, fs, clock, opened, lines)
        Ok(transcript): Ok(transcript)
        Error(why): Error(Unopened(dir: dir, why: why))
      end
  end
end

# Serves a folder until jobq is stopped. A log whose last line was cut short is compacted first,
# so the next record starts on a line of its own.
fn serve(http: Http, fs: Fs, clock: Clock, err: Out, place: Place) : Result(String, Problem)
  opened = try opened_store(fs, err, place.dir)
  whole = if cut_short?(opened): try compacted_store(fs, place.dir, opened) else: opened
  case http.listen(place.port, within: 5_000.ms)
    Ok(listener):
      queue = Queue.start(fs, opening(whole, clock.now))
      listener.serve(into: Acceptor.start(queue, clock), idle: 5_000.ms)
      Ok("jobq: serving #{place.dir} on 127.0.0.1:#{listener.port}\n")
    Error(_): Error(Unbound(port: place.port))
  end
end

fn compacted_store(fs: Fs, dir: String, opened: Table) : Result(Table, Problem)
  case compact(fs, opened)
    Ok(table): Ok(table)
    Error(_): Error(Unopened(dir: dir, why: "holds a jobq.log jobq could not rewrite"))
  end
end

fn compacted(fs: Fs, dir: String, opened: Table) : Result(String, Problem)
  table = try compacted_store(fs, dir, opened)
  Ok("jobq: compacted #{dir}/jobq.log from #{lines(opened)} lines to #{count(table)}\n")
end

fn script_of(fs: Fs, script: String) : Result(List(String), Problem)
  case fs.read_only.read_lines(script, within: 10_000.ms)
    Ok(lines): Ok(lines)
    Error(Missing(_)): Error(Unopened(dir: script, why: "is not a script jobq can read"))
    Error(Timeout): Error(Unopened(dir: script, why: "took longer than 10 seconds to read"))
    Error(NotText): Error(Unopened(dir: script, why: "is not UTF-8 text"))
  end
end

# The folder's store, replayed. A last line cut short is left out and said on stderr.
fn opened_store(fs: Fs, err: Out, dir: String) : Result(Table, Problem)
  case open(fs, dir)
    Ok(table):
      if cut_short?(table)
        err.write_line("jobq: the last line of #{dir}/jobq.log was cut short, so it is left out")
        err.flush
      end
      Ok(table)
    Error(problem): Error(Unopened(dir: dir, why: why_unopened(problem)))
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
    Unbound(port): "cannot listen on 127.0.0.1:#{port}"
    Unreached(why): why
  end
end

fn code_of(problem: Problem) : UInt8
  case problem
    Usage(_): 2
    Unopened(dir: _, why: _) | Unbound(_) | Unreached(_): 1
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
  assert task(["serve", "data"]) == Ok(Serving(place: Place(dir: "data", port: 7_900)))
  assert task(["serve",
    "data",
    "--port",
    "8000"]) == Ok(Serving(place: Place(dir: "data", port: 8_000)))
  assert serving?(["serve", "data"]) and !serving?(["compact", "data"])
end

test "a missing folder, a bad port, a short request, or an unknown command is a usage error"
  assert task([]) is Error(Usage(_))
  assert task(["serve"]) is Error(Usage(_))
  assert task(["serve", "--port", "8000"]) is Error(Usage(_))
  assert task(["serve", "data", "--port", "0"]) is Error(Usage(_))
  assert task(["serve", "data", "--port", "65536"]) is Error(Usage(_))
  assert task(["compact", "a", "b"]) is Error(Usage(_))
  assert task(["client", "localhost", "7900", "ada", "GET"]) is Error(Usage(_))
  assert task(["client", "localhost", "port", "ada", "GET", "/jobs"]) is Error(Usage(_))
  assert task(["check", "data"]) is Error(Usage(_))
  assert task(["stop"]) is Error(Usage(_))
  assert code_of(Usage(detail: "x")) == 2
end

test "client and check read their arguments"
  words = ["client", "localhost", "7900", "ada", "POST", "/jobs", "{\"queue\":", "\"q\"}"]
  assert task(words) is Ok(Asking(trip))
  assert trip.json == "{\"queue\": \"q\"}" and trip.port == 7_900
  assert task(["check", "data", "s.txt"]) == Ok(Checking(dir: "data", script: "s.txt"))
end

test "a store whose last line was cut short opens without it and says so on stderr; a folder that is not there exits 1"
  fs = Fs.fixture()
  err = Out.fixture()
  assert fs.write("d/jobq.log", "SET ids 101\nSET j_1 {", within: 1_000.ms) is Ok(_)
  assert opened_store(fs, err, "d") is Ok(table)
  assert count(table) == 1
  assert err.written == ["jobq: the last line of d/jobq.log was cut short, so it is left out\n"]
  assert opened_store(fs, err, "nowhere") is Error(problem)
  assert code_of(problem) == 1
  assert said(problem) == "nowhere is not a folder jobq can read"
end

verified: types, contracts, tests (4), property (0 seeds), sim (not run)
          proven: not run
