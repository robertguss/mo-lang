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

use Kv.Log{Journal, LogError, Opened, compacted, open}
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
  "usage: kv serve <dir> [--port N] | kv compact <dir> | kv client <host> <port> <line> | kv check <dir> <script>"
end

fn command(args: List(String)) : Result(Command, Problem)
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

fn serving(args: List(String)) : Result(Command, Problem)
  dir = try dir_of(args)
  flags = args.drop(1)
  return Ok(Serving(dir: dir, port: 7_700)) if flags.size == 0
  if flags.size != 2 or flags.first != Some("--port")
    return Error(Usage(detail: "serve takes a folder and then --port N"))
  end
  port = try port_of(flags.get(1) or "")
  Ok(Serving(dir: dir, port: port))
end

fn compacting(args: List(String)) : Result(Command, Problem)
  dir = try dir_of(args)
  return Error(Usage(detail: "compact takes one folder")) if args.size != 1
  Ok(Compacting(dir: dir))
end

fn asking(args: List(String)) : Result(Command, Problem)
  if args.size < 4
    return Error(Usage(detail: "client takes a host, a port, and a request"))
  end
  port = try port_of(args.get(1) or "")
  Ok(Asking(host: args.first or "", port: port, line: String.join(args.drop(2), " ")))
end

fn checking(args: List(String)) : Result(Command, Problem)
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

fn ran(net: Net, fs: Fs, clock: Clock, err: Out, args: List(String)) : Result(String, Problem)
  given = try command(args)
  case given
    Serving(dir: dir, port: port):
      folder = fs.scoped(dir)
      opened = try opened_log(folder, err, dir)
      serve(net, folder, clock, opened, port)
    Compacting(dir):
      folder = fs.scoped(dir)
      opened = try opened_log(folder, err, dir)
      compact(folder, dir, opened)
    Asking(host: host, port: port, line: line): client(net, host, port, line)
    Checking(dir: dir, script: script):
      lines = try script_of(fs, script)
      folder = fs.scoped(dir)
      opened = try opened_log(folder, err, dir)
      check(net, folder, clock, opened, lines)
  end
end

fn serve(net: Net, folder: Fs, clock: Clock, opened: Opened, port: UInt16) : Result(String, Problem)
  case net.listen(port, within: 10_000.ms)
    Ok(listener): Ok(served_on(listener, folder, clock, opened))
    Error(_): Error(Unbound(port: port))
  end
end

# The log rewritten as one line per live key: written whole beside the log, then renamed over
# it, so a compaction cut short leaves the old log as it was.
fn compact(folder: Fs, dir: String, opened: Opened) : Result(String, Problem)
  text = compacted(opened.replayed.table)
  if folder.write("kv.compacted.log", text, within: 60_000.ms) is Error(_)
    return Error(Unopened(dir: dir, why: "holds a kv.log kv could not rewrite"))
  end
  if folder.rename("kv.compacted.log", "kv.log", within: 60_000.ms) is Error(_)
    return Error(Unopened(dir: dir, why: "holds a kv.log kv could not rename"))
  end
  Ok(rewritten(dir, opened))
end

# What compaction says it did: the lines the log held, and the live keys it now holds.
fn rewritten(dir: String, opened: Opened) : String
  "kv: compacted #{dir}/kv.log from #{opened.replayed.lines} lines to #{opened.replayed.table.size}\n"
end

# Serves every client of the listener from here on; the runtime owns the loop, so kv serves
# until it is stopped.
fn served_on(listener: Listener, folder: Fs, clock: Clock, opened: Opened) : String
  listener.serve(into: started(folder, "kv.log", opened, clock), idle: 60_000.ms)
  "kv: serving on 127.0.0.1:#{listener.port}\n"
end

# The store, its journal appending to the file `log` in the folder, the gate, and the
# listening process, over a log just opened.
fn started(folder: Fs, log: String, opened: Opened, clock: Clock) : Handle(Listening)
  journal = Journal.start(folder, log, opened.bytes)
  opening = Opening(table: opened.replayed.table, log_bytes: opened.bytes, at: clock.now,
    log_within: 30_000.ms)
  Listening.start(Store.start(journal, clock, opening), Gate.start())
end

# Reads one line of its connection per message, so a client takes an answer of several lines
# one round trip at a time.
process Reply(conn: Conn)
  state
    read: UInt64
  end

  message Next : Result(Option(String), NetError)

  fn update(state, message)
    case message
      Next:
        state.read += 1
        conn.read_line(within: 30_000.ms)
    end
  end
end

supervisor Replies(conn: Conn)
  child Reply(conn), restart: :never
end

# One request over a connection of its own, and the lines of its answer.
fn client(net: Net, host: String, port: UInt16, line: String) : Result(String, Problem)
  case exchanged(net, host, port, line)
    Ok(text): Ok(text)
    Error(_): Error(Unreached(host: host, port: port))
  end
end

fn exchanged(net: Net, host: String, port: UInt16, line: String) : Result(String, NetError)
  conn = try net.connect(host, port, within: 10_000.ms)
  reply = Reply.start(conn)
  try conn.write("#{line}\n", within: 10_000.ms)
  first = try next_line(reply)
  head = first or ""
  var text = "#{head}\n"
  for _ in 0..follows(head)
    more = try next_line(reply)
    text = "#{text}#{more or ""}\n"
  end
  conn.close
  Ok(text)
end

fn next_line(reply: Handle(Reply)) : Result(Option(String), NetError)
  case reply.ask(Next, within: 30_000.ms)
    Ok(outcome): outcome
    Error(_): Error(Timeout)
  end
end

# Serves a folder's log on a free port and plays a script through kv's own client, each line
# over a connection of its own; the transcript is every line sent and what came back. The
# folder's log is only read: the changes go to kv.check.log beside it, removed at the end.
fn check(net: Net, folder: Fs, clock: Clock, opened: Opened, lines: List(String)) : Result(String,
  Problem)
  case net.listen(0, within: 10_000.ms)
    Ok(listener):
      cleared(folder)
      transcript = checked_on(net, listener, folder, clock, opened, lines)
      cleared(folder)
      Ok(transcript)
    Error(_): Error(Unbound(port: 0))
  end
end

# The check writes to a log of its own beside the folder's, gone before and after the script.
fn cleared(folder: Fs) : Bool
  removed = folder.remove("kv.check.log", within: 10_000.ms) is Ok(_)
  removed or folder.size("kv.check.log", within: 10_000.ms) is Error(Missing(_))
end

fn checked_on(net: Net, listener: Listener, folder: Fs, clock: Clock, opened: Opened,
  lines: List(String)) : String
  listener.serve(into: started(folder, "kv.check.log", opened, clock), idle: 60_000.ms)
  var transcript = ""
  for line in lines
    heard = shown(client(net, "127.0.0.1", listener.port, line))
    transcript = "#{transcript}> #{line}\n#{heard}"
  end
  transcript
end

fn shown(heard: Result(String, Problem)) : String
  case heard
    Ok(text): text
    Error(problem): "#{said(problem)}\n"
  end
end

fn script_of(fs: Fs, script: String) : Result(List(String), Problem)
  case fs.read_only.read_lines(script, within: 10_000.ms)
    Ok(lines): Ok(lines)
    Error(Missing(_)): Error(Unopened(dir: script, why: "is not a script kv can read"))
    Error(Timeout): Error(Unopened(dir: script, why: "took longer than ten seconds to read"))
    Error(NotText): Error(Unopened(dir: script, why: "is not UTF-8 text"))
  end
end

# The folder's log, replayed. A last line cut short is left out and said on stderr, once, at
# once.
fn opened_log(dir: Fs, err: Out, name: String) : Result(Opened, Problem)
  case open(dir)
    Ok(opened):
      if opened.replayed.truncated
        err.write_line("kv: the last line of #{name}/kv.log was cut short, so it is left out")
        err.flush
      end
      Ok(opened)
    Error(problem): Error(Unopened(dir: name, why: why_unopened(problem)))
  end
end

fn why_unopened(problem: LogError) : String
  case problem
    NoFolder: "is not a folder kv can read"
    Unreadable: "holds a kv.log kv cannot read"
    Slow: "took longer than ten seconds to read"
    BadLine(number): "holds a kv.log whose line #{number} is not a SET or a DEL"
  end
end

fn said(problem: Problem) : String
  case problem
    Usage(detail): "#{detail}; #{usage()}"
    Unopened(dir: dir, why: why): "#{dir} #{why}"
    Unbound(port): "cannot listen on 127.0.0.1:#{port}"
    Unreached(host: host, port: port): "no kv answered at #{host}:#{port}"
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

# Whether the arguments say to serve, which goes on until kv is stopped.
fn serving?(args: List(String)) : Bool
  command(args) is Ok(Serving(dir: _, port: _))
end

# Serving goes on until kv is stopped; every other command ends kv with exit once it is done,
# since check serves a listener of its own.
fn main(platform: Platform)
  args = platform.args
  case ran(platform.net, platform.fs, platform.clock, platform.stderr, args)
    Ok(text):
      platform.stdout.write(text)
      platform.stdout.flush
      if !serving?(args)
        platform.exit(0)
      end
    Error(problem):
      platform.stderr.write_line("kv: #{said(problem)}")
      platform.exit(code_of(problem))
  end
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

verified: types, contracts, tests (5), property (0 seeds), sim (not run)
          proven: not run
