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

fn ran(http: Http, fs: Fs, clock: Clock, err: Out, args: List(String)) : Result(String, Problem)
  # body gone; regenerate
end

# The journal over the folder, opened before the listener is served, so a folder that cannot be
# read exits 1 and a log of any size is replayed before the first request: the ask waits ten
# minutes, and the replay runs on what remains of them.
fn opened_journal(fs: Fs, clock: Clock, err: Out, place: Place) : Result(Handle(Journal), Problem)
  # body gone; regenerate
end

# Serves a folder until the ledger is stopped; the runtime owns the loop. A request not whole
# within 5 seconds of its connection is closed.
fn serve(http: Http, fs: Fs, clock: Clock, err: Out, spot: Spot) : Result(String, Problem)
  # body gone; regenerate
end

fn compacted(fs: Fs, err: Out, dir: String) : Result(String, Problem)
  # body gone; regenerate
end

# Serves a folder's ledger on a free port, its changes going to ledger.check.log beside its
# ledger.log, removed before the journal opens and after the script, and plays the script.
fn checking_folder(http: Http, fs: Fs, clock: Clock, err: Out, dir: String,
  script: String) : Result(String, Problem)
  # body gone; regenerate
end

fn script_of(fs: Fs, script: String) : Result(List(String), Problem)
  # body gone; regenerate
end

fn cleared(folder: Fs) : Bool
  # body gone; regenerate
end

fn said(problem: Problem) : String
  # body gone; regenerate
end

fn code_of(problem: Problem) : UInt8
  # body gone; regenerate
end

# Whether the arguments say to serve, which goes on until the ledger is stopped.
fn serving?(args: List(String)) : Bool
  # body gone; regenerate
end

fn main(platform: Platform)
  # body gone; regenerate
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
