# run: check data/demo data/session.txt
# run: compact data/compact
# run: serve
# exit: 2
# run: serve data/nowhere
# exit: 1
# run: client 127.0.0.1 1 ada GET /health
# exit: 1
module Ledger.Main
expose Task, Spot, Problem, task, serving?, main

use Ledger.Check{Trip, trip_of, client, checked, said_unreached}
use Ledger.Journal{Journal, Readiness}
use Ledger.Records{Place}
use Ledger.Server{Acceptor}
use Ledger.Store{open, compact, cut_short?, lines, count}

intent "Run the ledger: serve a folder's ledger over HTTP, compact its log to one line per live record, send one request as a client, or check a folder by serving it on a free port and playing a script through the client; a usage error exits 2, and a folder or port that cannot be had exits 1."

# Where to serve: the folder and the port.
struct Spot
  dir: String
  port: UInt16
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
  "usage: ledger serve <dir> [--port N] | ledger compact <dir> | ledger client <host> <port> <token> <method> <path> [<json>] [--key K] | ledger check <dir> <script>"
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
  return Ok(Serving(spot: Spot(dir: dir, port: 7_910))) if flags.size == 0
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
  case trip_of(args.drop(2), args.first or "", port)
    Some(trip): Ok(Asking(trip: trip))
    None: Error(Usage(detail: "a request is a token, a method, a path, any JSON, and --key K"))
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

fn ran(http: Http, fs: Fs, clock: Clock, err: Out, args: List(String)) : Result(String, Problem)
  given = try task(args)
  case given
    Serving(spot): serve(http, fs, clock, err, spot)
    Compacting(dir): compacted(fs, err, dir)
    Asking(trip):
      case client(http, trip)
        Some(text): Ok(text)
        None: Error(Unreached(host: trip.host, port: trip.port))
      end
    Checking(dir: dir, script: script): checking_folder(http, fs, clock, err, dir, script)
  end
end

# The journal over the folder, opened before the listener is served, so a folder that cannot be
# read exits 1 and a log of any size is replayed before the first request: the ask waits ten
# minutes, and the replay runs on what remains of them.
fn opened_journal(fs: Fs, clock: Clock, err: Out, place: Place) : Result(Handle(Journal), Problem)
  journal = Journal.start(fs, clock, place, clock.now)
  case journal.ask(Open(me: journal), within: 600_000.ms)
    Ok(Ready(accounts: _, entries: _, torn: torn)):
      if torn
        err.write_line("ledger: #{place.dir}/#{place.log} ends in part of a batch, which is left out")
        err.flush
      end
      Ok(journal)
    Ok(Unready(why)): Error(Unopened(dir: place.dir, why: why))
    Error(_): Error(Unopened(dir: place.dir, why: "took longer than ten minutes to open"))
  end
end

# Serves a folder until the ledger is stopped; the runtime owns the loop. A request not whole
# within 5 seconds of its connection is closed.
fn serve(http: Http, fs: Fs, clock: Clock, err: Out, spot: Spot) : Result(String, Problem)
  journal = try opened_journal(fs, clock, err, Place(dir: spot.dir, log: "ledger.log"))
  case http.listen(spot.port, within: 5_000.ms)
    Ok(listener):
      listener.serve(into: Acceptor.start(journal), idle: 5_000.ms)
      Ok("ledger: serving #{spot.dir} on 127.0.0.1:#{listener.port}\n")
    Error(_): Error(Unbound(port: spot.port))
  end
end

fn compacted(fs: Fs, err: Out, dir: String) : Result(String, Problem)
  case open(fs, dir)
    Ok(table):
      if cut_short?(table)
        err.write_line("ledger: #{dir}/ledger.log ends in part of a batch, which is left out")
      end
      case compact(fs, table)
        Ok(whole):
          Ok("ledger: compacted #{dir}/ledger.log from #{lines(table)} lines to #{count(whole)}\n")
        Error(_): Error(Unopened(dir: dir, why: "holds a ledger.log the ledger could not rewrite"))
      end
    Error(_):
      Error(Unopened(dir: dir, why: "is not a folder with a ledger.log the ledger can read"))
  end
end

# Serves a folder's ledger on a free port, its changes going to ledger.check.log beside its
# ledger.log, removed before the journal opens and after the script, and plays the script.
fn checking_folder(http: Http, fs: Fs, clock: Clock, err: Out, dir: String,
  script: String) : Result(String, Problem)
  lines_read = try script_of(fs, script)
  return Error(Unopened(dir: dir,
    why: "holds a ledger.check.log the ledger cannot remove")) if !cleared(fs.scoped(dir))
  journal = try opened_journal(fs, clock, err, Place(dir: dir, log: "ledger.check.log"))
  case http.listen(0, within: 5_000.ms)
    Ok(listener):
      listener.serve(into: Acceptor.start(journal), idle: 5_000.ms)
      transcript = checked(http, clock, listener.port, lines_read)
      return Ok(transcript) if cleared(fs.scoped(dir))
      Error(Unopened(dir: dir, why: "holds a ledger.check.log the ledger cannot remove"))
    Error(_): Error(Unbound(port: 0))
  end
end

fn script_of(fs: Fs, script: String) : Result(List(String), Problem)
  case fs.read_only.read_lines(script, within: 10_000.ms)
    Ok(found): Ok(found)
    Error(_): Error(Unopened(dir: script, why: "is not a script the ledger can read"))
  end
end

fn cleared(folder: Fs) : Bool
  removed = folder.remove("ledger.check.log", within: 10_000.ms) is Ok(_)
  removed or folder.size("ledger.check.log", within: 10_000.ms) is Error(Missing(_))
end

fn said(problem: Problem) : String
  case problem
    Usage(detail): "#{detail}; #{usage()}"
    Unopened(dir: dir, why: why): "#{dir} #{why}"
    Unbound(port): "cannot listen on 127.0.0.1:#{port}"
    Unreached(host: host, port: port): said_unreached(host, port)
  end
end

fn code_of(problem: Problem) : UInt8
  case problem
    Usage(_): 2
    Unopened(dir: _, why: _) | Unbound(_) | Unreached(host: _, port: _): 1
  end
end

# Whether the arguments say to serve, which goes on until the ledger is stopped.
fn serving?(args: List(String)) : Bool
  task(args) is Ok(Serving(_))
end

fn main(platform: Platform)
  args = platform.args
  case ran(platform.http, platform.fs, platform.clock, platform.stderr, args)
    Ok(text):
      platform.stdout.write(text)
      platform.stdout.flush
      if !serving?(args)
        platform.exit(0)
      end
    Error(problem):
      platform.stderr.write_line("ledger: #{said(problem)}")
      platform.exit(code_of(problem))
  end
end

test "serve takes a folder and an optional port, 7910 by default"
  assert task(["serve", "data"]) == Ok(Serving(spot: Spot(dir: "data", port: 7_910)))
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
  assert task(["serve", "data", "--port", "0"]) is Error(Usage(_))
  assert task(["compact", "a", "b"]) is Error(Usage(_))
  assert task(["client", "localhost", "7910", "ada", "GET"]) is Error(Usage(_))
  assert task(["client", "localhost", "port", "ada", "GET", "/health"]) is Error(Usage(_))
  assert task(["check", "data"]) is Error(Usage(_))
  assert task(["stop"]) is Error(Usage(_))
end

test "a usage error exits 2, and a folder or port that cannot be had exits 1"
  assert code_of(Usage(detail: "x")) == 2
  assert code_of(Unopened(dir: "d", why: "w")) == 1
  assert code_of(Unbound(port: 7_910)) == 1
  assert code_of(Unreached(host: "h", port: 1)) == 1
end

verified: types, contracts, tests (3), property (0 seeds), sim (not run)
          proven: not run
