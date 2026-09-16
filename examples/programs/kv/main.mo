# run: check data/demo data/session.txt
# run: compact data/compact
# run: serve
# exit: 2
# run: serve data/nowhere
# exit: 1
# run: client 127.0.0.1 1 GET greeting
# exit: 1
module Kv.Main
expose Command, Problem, Reply, Replies, command, serving?, main

use Kv.Log{Journal, Opened, compacted, open}
use Kv.Protocol{follows}
use Kv.Server{Gate, Listening}
use Kv.Store{Store, Opening}

intent "Run kv: serve a folder's log over TCP, compact a log to one line per live key, send one request as a client, or check a folder by serving it on a free port and playing a script through the client; a usage error exits 2, and a folder or port that cannot be had exits 1."

enum Command
  Serving(dir: String, port: UInt16)
  Compacting(dir: String)
  Asking(host: String, port: UInt16, line: String)
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

fn command(args: List(String)) : Result(Command, Problem)
  # body gone; regenerate
end

fn serving(args: List(String)) : Result(Command, Problem)
  # body gone; regenerate
end

fn compacting(args: List(String)) : Result(Command, Problem)
  # body gone; regenerate
end

fn asking(args: List(String)) : Result(Command, Problem)
  # body gone; regenerate
end

fn checking(args: List(String)) : Result(Command, Problem)
  # body gone; regenerate
end

fn dir_of(args: List(String)) : Result(String, Problem)
  # body gone; regenerate
end

fn port_of(text: String) : Result(UInt16, Problem)
  ensures result is Ok(port) implies port >= 1
  # body gone; regenerate
end

fn ran(net: Net, fs: Fs, clock: Clock, err: Out, args: List(String)) : Result(String, Problem)
  # body gone; regenerate
end

fn serve(net: Net, folder: Fs, clock: Clock, opened: Opened, port: UInt16) : Result(String, Problem)
  # body gone; regenerate
end

# The log rewritten as one line per live key: written whole beside the log, then renamed over
# it, so a compaction cut short leaves the old log as it was.
fn compact(folder: Fs, dir: String, opened: Opened) : Result(String, Problem)
  # body gone; regenerate
end

# Serves every client of the listener from here on; the runtime owns the loop, so kv serves
# until it is stopped.
fn served_on(listener: Listener, folder: Fs, clock: Clock, opened: Opened) : String
  # body gone; regenerate
end

# The store, its journal appending to the file `log` in the folder, the gate, and the
# listening process, over a log just opened.
fn started(folder: Fs, log: String, opened: Opened, clock: Clock) : Handle(Listening)
  # body gone; regenerate
end

# Reads one line of its connection per message, so a client takes an answer of several lines
# one round trip at a time.
process Reply(conn: Conn)
  state
    read: UInt64
  end

  message Next : Result(Option(String), NetError)

  fn update(state, message)
    # body gone; regenerate
  end
end

supervisor Replies(conn: Conn)
  child Reply(conn), restart: :never
end

# One request over a connection of its own, and the lines of its answer.
fn client(net: Net, host: String, port: UInt16, line: String) : Result(String, Problem)
  # body gone; regenerate
end

fn exchanged(net: Net, host: String, port: UInt16, line: String) : Result(String, NetError)
  # body gone; regenerate
end

fn next_line(reply: Handle(Reply)) : Result(Option(String), NetError)
  # body gone; regenerate
end

# Serves a folder's log on a free port and plays a script through kv's own client, each line
# over a connection of its own; the transcript is every line sent and what came back. The
# folder's log is only read: the changes go to kv.check.log beside it, removed at the end.
fn check(net: Net, folder: Fs, clock: Clock, opened: Opened, lines: List(String)) : Result(String,
  # body gone; regenerate
end

fn checked_on(net: Net, listener: Listener, folder: Fs, clock: Clock, opened: Opened,
  lines: List(String)) : String
  # body gone; regenerate
end

fn shown(heard: Result(String, Problem)) : String
  # body gone; regenerate
end

fn script_of(fs: Fs, script: String) : Result(List(String), Problem)
  # body gone; regenerate
end

# The folder's log, replayed. A last line cut short is left out and said on stderr, once, at
# once.
fn opened_log(dir: Fs, err: Out, name: String) : Result(Opened, Problem)
  # body gone; regenerate
end

fn said(problem: Problem) : String
  # body gone; regenerate
end

fn code_of(problem: Problem) : UInt8
  # body gone; regenerate
end

# Whether the arguments say to serve, which goes on until kv is stopped.
fn serving?(args: List(String)) : Bool
  # body gone; regenerate
end

# Serving goes on until kv is stopped; every other command ends kv with exit once it is done,
# since check serves a listener of its own.
fn main(platform: Platform)
  # body gone; regenerate
end

test "serve takes a folder and an optional port, 7700 by default"
  assert command(["serve", "data"]) == Ok(Serving(dir: "data", port: 7_700))
  assert serving?(["serve", "data"])
  assert !serving?(["check", "data", "s.txt"])
  assert command(["serve", "data", "--port", "8000"]) == Ok(Serving(dir: "data", port: 8_000))
end

test "a missing folder, a bad port, or an unknown command is a usage error"
  assert command([]) is Error(Usage(_))
  assert command(["serve"]) is Error(Usage(_))
  assert command(["serve", "--port", "8000"]) is Error(Usage(_))
  assert command(["serve", "data", "--port"]) is Error(Usage(_))
  assert command(["serve", "data", "--port", "0"]) is Error(Usage(_))
  assert command(["serve", "data", "--port", "65536"]) is Error(Usage(_))
  assert command(["serve", "data", "--port", "http"]) is Error(Usage(_))
  assert command(["compact"]) is Error(Usage(_))
  assert command(["compact", "a", "b"]) is Error(Usage(_))
  assert command(["client", "localhost", "7700"]) is Error(Usage(_))
  assert command(["stop"]) is Error(Usage(_))
end

test "client joins the rest of its arguments into one line"
  assert command(["client",
    "localhost",
    "7700",
    "SET",
    "a",
    "two",
    "words"]) == Ok(Asking(host: "localhost", port: 7_700, line: "SET a two words"))
  assert command(["compact", "data"]) == Ok(Compacting(dir: "data"))
  assert command(["check", "data", "s.txt"]) == Ok(Checking(dir: "data", script: "s.txt"))
end

test "a log whose last line was cut short opens without it, and says so on the error stream"
  dir = Fs.fixture()
  err = Out.fixture()
  assert dir.write("kv.log", "SET a 1\nSET b 2", within: 1_000.ms) is Ok(_)
  assert opened_log(dir, err, "d") is Ok(opened)
  assert opened.replayed.lines == 1
  assert err.written == ["kv: the last line of d/kv.log was cut short, so it is left out\n"]
end

test "a usage error exits 2, and a folder or port that cannot be had exits 1"
  assert code_of(Usage(detail: "x")) == 2
  assert code_of(Unopened(dir: "d", why: "w")) == 1
  assert code_of(Unbound(port: 7_700)) == 1
  assert code_of(Unreached(host: "h", port: 1)) == 1
end
