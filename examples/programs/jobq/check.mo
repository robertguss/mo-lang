module Jobq.Check
expose check, steady, crowd_size

use Jobq.Client{trip_of, asked}
use Jobq.Queue{Queue, opening}
use Jobq.Server{Acceptor}
use Jobq.Store{Table, writing_to}

intent "Check a folder: serve its jobs on a free port and play a script through the client over a real socket, a request a line, with the times that depend on the clock steadied; a crowd N line opens N connections that send nothing and keeps them open to the script's end. The folder's log is only read: the changes go to jobq.check.log beside it, removed before and after."

fn check(http: Http, net: Net, fs: Fs, clock: Clock, opened: Table,
  lines: List(String)) : Result(String, String)
  folder = fs.scoped(opened.dir)
  return Error("holds a jobq.check.log jobq cannot remove") if !cleared(folder)
  case http.listen(0, within: 5_000.ms)
    Ok(listener):
      queue = Queue.start(fs, opening(writing_to(opened, "jobq.check.log"), clock.now))
      listener.serve(into: Acceptor.start(queue, clock), idle: 5_000.ms)
      transcript = played(http, net, listener.port, lines)
      return Ok(transcript) if cleared(folder)
      Error("holds a jobq.check.log jobq cannot remove")
    Error(_): Error("cannot listen on a free port of 127.0.0.1")
  end
end

fn cleared(folder: Fs) : Bool
  removed = folder.remove("jobq.check.log", within: 10_000.ms) is Ok(_)
  removed or folder.size("jobq.check.log", within: 10_000.ms) is Error(Missing(_))
end

# Plays each line in turn. A crowd line's connections go in a list kept to the script's end, so
# they stay open, sending nothing, while the lines after it are answered.
fn played(http: Http, net: Net, port: UInt16, lines: List(String)) : String
  var transcript = ""
  var crowd = []
  for line in lines
    wanted = crowd_size(line)
    for _ in 0..wanted
      if net.connect("127.0.0.1", port, within: 5_000.ms) is Ok(conn)
        crowd = crowd.push(conn)
      end
    end
    heard = if wanted > 0
      "#{crowd.size} connections open, none sending\n"
    else
      heard_line(http, line, port)
    end
    transcript = "#{transcript}> #{line}\n#{heard}"
  end
  transcript
end

fn heard_line(http: Http, line: String, port: UInt16) : String
  case trip_of(line.split(" "), "127.0.0.1", port)
    Ok(trip):
      case asked(http, trip)
        Ok(text): steady(text)
        Error(why): "#{why}\n"
      end
    Error(why): "#{why}\n"
  end
end

# How many quiet connections a crowd N line asks for; 0 for any other line.
fn crowd_size(line: String) : UInt64
  return 0 if !line.starts_with?("crowd ")
  line.slice(6, line.size).to_u64 or 0
end

# A transcript with what depends on the clock replaced: each job's times, its lease's end, and the
# service's uptime.
fn steady(text: String) : String
  times = masked(masked(text, "created_at", true), "updated_at", true)
  masked(masked(times, "lease_until", true), "uptime_ms", false)
end

fn masked(text: String, key: String, quoted: Bool) : String
  label = "\"#{key}\": "
  pieces = text.split(label)
  mark = if quoted: "\"<#{key}>\"" else: "<#{key}>"
  rest = pieces.drop(1).map(fn(piece) "#{label}#{mark}#{after_value(piece, quoted)}" end)
  String.join([pieces.first or ""].concat(rest), "")
end

# What follows a JSON value at the start of a piece: past the closing quote of a string, or from
# the first , or } after a number.
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

test "the clock's values are steadied, and nothing else"
  job = "{\"id\": \"j_1\", \"created_at\": \"2026-09-14T09:00:00.123Z\", \"updated_at\": \"2026-09-14T09:00:01Z\", \"worker\": \"ada\", \"lease_until\": \"2026-09-14T09:01:01Z\"}"
  want = "{\"id\": \"j_1\", \"created_at\": \"<created_at>\", \"updated_at\": \"<updated_at>\", \"worker\": \"ada\", \"lease_until\": \"<lease_until>\"}"
  assert steady(job) == want
  assert steady("{\"queued\": 1, \"uptime_ms\": 1234}") == "{\"queued\": 1, \"uptime_ms\": <uptime_ms>}"
  assert steady("204\n") == "204\n"
end

test "a crowd line names how many quiet connections to open"
  assert crowd_size("crowd 1200") == 1_200
  assert crowd_size("ada GET /jobs") == 0
  assert crowd_size("crowd many") == 0
end

test "a check log left behind is removed, and a folder with none is clear"
  fs = Fs.fixture()
  assert fs.write("d/jobq.check.log", "SET a 1\n", within: 1.minute) is Ok(_)
  assert cleared(fs.scoped("d"))
  assert fs.read("d/jobq.check.log", within: 1.minute) is Error(Missing(_))
  assert cleared(fs.scoped("d"))
end
