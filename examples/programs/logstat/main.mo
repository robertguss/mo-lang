# run: logstat/fixture
# run: logstat/fixture --json
# run: --top 2 logstat/fixture --since 2026-09-12T10:01:00Z
# run: logstat/fixture --top 101
# exit: 2
# run: logstat/fixture/nowhere
# exit: 1
module Logstat.Main
expose Options, Problem, options, main

use Logstat.Report{json, text}
use Logstat.Stats{Summary, counted, empty, malformed_line}

intent "Run logstat <dir> [--top N] [--since <ISO-8601>] [--json]: summarize every .log file directly inside the folder, in name order, one file at a time and only reading; a usage error exits 2 with one line on stderr, and a folder with no .log file exits 1."

struct Options
  dir: String
  top: UInt64
  since: Option(Time)
  as_json: Bool
end

enum Problem
  Usage(detail: String)
  NoLogs(dir: String)
  Unread(name: String, why: String)
end

fn usage() : String
  "usage: logstat <dir> [--top N] [--since <ISO-8601>] [--json]"
end

fn options(args: List(String)) : Result(Options, Problem)
  ensures result is Ok(given) implies given.top >= 1 and given.top <= 100 and given.dir != ""

  repeated = ["--top", "--since", "--json"].find(fn(flag) args.count(fn(a) a == flag end) > 1 end)
  if repeated is Some(flag)
    return Error(Usage(detail: "#{flag} is given twice"))
  end
  given = try flagged(Options(dir: "", top: 5, since: None, as_json: false), args)
  return Error(Usage(detail: "no folder given")) if given.dir == ""
  Ok(given)
end

# The options so far, and the words not read yet.
fn flagged(so_far: Options, words: List(String)) : Result(Options, Problem)
  return Ok(so_far) if words.size == 0
  word = words.first or ""
  var next = so_far
  case word
    "--json":
      next.as_json = true
    "--top":
      next.top = try top_of(words.get(1))
    "--since":
      next.since = Some(try since_of(words.get(1)))
    _:
      next.dir = try dir_of(so_far.dir, word)
  end
  flagged(next, words.drop(if word == "--top" or word == "--since": 2 else: 1))
end

fn top_of(word: Option(String)) : Result(UInt64, Problem)
  ensures result is Ok(n) implies n >= 1 and n <= 100

  n = (word or "").to_u64 or 0
  return Ok(n) if n >= 1 and n <= 100
  Error(Usage(detail: "--top takes a number from 1 to 100, not #{word or "nothing"}"))
end

fn since_of(word: Option(String)) : Result(Time, Problem)
  case Time.parse(word or "")
    Some(since): Ok(since)
    None: Error(Usage(detail: "--since takes an ISO-8601 time, not #{word or "nothing"}"))
  end
end

fn dir_of(dir: String, word: String) : Result(String, Problem)
  return Error(Usage(detail: "unknown flag #{word}")) if word.starts_with?("-")
  return Error(Usage(detail: "one folder only, not #{dir} and #{word}")) if dir != ""
  Ok(word)
end

# Every .log file directly inside the folder, folded into one summary a file at a time; a .log
# name that is not a file, such as a folder, is passed over.
fn summarized(fs: Fs, given: Options) : Result(Summary, Problem)
  logs = fs.scoped(given.dir).read_only
  names = try log_names(logs, given.dir)
  var summary = empty(given.top, given.since)
  var read = 0
  for name in names
    outcome = try folded(logs, name, summary)
    read += if outcome is Some(_): 1 else: 0
    summary = outcome or summary
  end
  return Error(NoLogs(dir: given.dir)) if read == 0
  Ok(summary)
end

fn log_names(logs: Fs, dir: String) : Result(List(String), Problem)
  case logs.list(within: 1.minute)
    Ok(names): Ok(names.filter(fn(name) name.ends_with?(".log") end))
    Error(Timeout): Error(Unread(name: dir, why: "took longer than a minute to list"))
    Error(Missing(_)) | Error(NotText): Error(NoLogs(dir: dir))
  end
end

# One file's lines folded into the summary as they are read; None when the name is not a file.
fn folded(logs: Fs, name: String, summary: Summary) : Result(Option(Summary), Problem)
  requires name.ends_with?(".log") and !name.contains?("/")

  case logs.fold_lines(name, summary, within: 10.minute, fn(s, line) counted(s, line) end)
    Ok(next): Ok(Some(next))
    Error(Missing(_)): Ok(None)
    Error(NotText): bytewise(logs, name, summary)
    Error(Timeout): Error(Unread(name: name, why: "took longer than ten minutes to read"))
  end
end

# A file with a line that is not UTF-8, read again whole as bytes, since fold_lines stops there:
# each such line is malformed.
fn bytewise(logs: Fs, name: String, summary: Summary) : Result(Option(Summary), Problem)
  case logs.read_bytes(name, within: 10.minute)
    Ok(bytes): Ok(Some(byte_lines(bytes).reduce(summary, fn(s, line) counted_bytes(s, line) end)))
    Error(Missing(_)): Ok(None)
    Error(Timeout): Error(Unread(name: name, why: "took longer than ten minutes to read"))
    Error(NotText): Error(Unread(name: name, why: "could not be read as bytes"))
  end
end

fn counted_bytes(summary: Summary, line: List(UInt8)) : Summary
  case String.from_bytes(line)
    Some(text): counted(summary, text)
    None: malformed_line(summary)
  end
end

# Bytes split at each newline as String.lines splits text: one carriage return before a newline is
# dropped, and a final newline starts no line.
fn byte_lines(bytes: List(UInt8)) : List(List(UInt8))
  return [] if bytes.size == 0
  breaks = bytes.enumerate.filter(fn(pair) pair.1 == 10 end).map(fn(pair) pair.0 end)
  starts = [0].concat(breaks.map(fn(at) at + 1 end))
  ends = breaks.concat([bytes.size])
  pieces = starts.zip(ends).map(fn(span) without_return(bytes.slice(span.0, span.1)) end)
  if bytes.last == Some(10): pieces.take(pieces.size - 1) else: pieces
end

fn without_return(line: List(UInt8)) : List(UInt8)
  if line.last == Some(13): line.take(line.size - 1) else: line
end

fn ran(fs: Fs, args: List(String)) : Result(String, Problem)
  given = try options(args)
  summary = try summarized(fs, given)
  Ok(if given.as_json: "#{json(summary)}\n" else: text(summary))
end

fn said(problem: Problem) : String
  case problem
    Usage(detail): "#{detail}; #{usage()}"
    NoLogs(dir): "no .log file in #{dir}"
    Unread(name: name, why: why): "#{name} #{why}"
  end
end

fn code_of(problem: Problem) : UInt8
  case problem
    Usage(_): 2
    NoLogs(_) | Unread(name: _, why: _): 1
  end
end

fn main(platform: Platform)
  case ran(platform.fs, platform.args)
    Ok(report): platform.stdout.write(report)
    Error(problem):
      platform.stderr.write_line("logstat: #{said(problem)}")
      platform.exit(code_of(problem))
  end
end

test "a folder and any of --top, --since, and --json, in any order"
  assert options(["logs"]) == Ok(Options(dir: "logs", top: 5, since: None, as_json: false))
  since = Time.from_parts(2026, 9, 12, 10, 1, 0)
  given = Options(dir: "logs", top: 100, since: Some(since), as_json: true)
  assert options(["--json", "--top", "100", "logs", "--since", "2026-09-12T10:01:00Z"]) == Ok(given)
  assert options(["logs", "--top", "1"]) is Ok(Options(dir: "logs", top: 1, since: None,
    as_json: false))
end

test "a top outside 1 to 100, a bad time, an unknown or repeated flag, and a missing or second folder are usage errors"
  assert options([]) is Error(Usage(_))
  assert options(["logs", "--top", "0"]) is Error(Usage(_))
  assert options(["logs", "--top", "101"]) is Error(Usage(_))
  assert options(["logs", "--top", "five"]) is Error(Usage(_))
  assert options(["logs", "--top"]) is Error(Usage(_))
  assert options(["logs", "--since", "yesterday"]) is Error(Usage(_))
  assert options(["logs", "--since"]) is Error(Usage(_))
  assert options(["logs", "--verbose"]) is Error(Usage(_))
  assert options(["logs", "--json", "--json"]) is Error(Usage(_))
  assert options(["logs", "more"]) is Error(Usage(_))
  assert options(["--json"]) is Error(Usage(_))
  assert code_of(Usage(detail: "no folder given")) == 2
  assert said(Usage(detail: "no folder given")) == "no folder given; #{usage()}"
end

test "every .log file directly inside the folder is read in name order, and nothing else"
  fs = Fs.fixture()
  assert fs.write("d/b.log", "2026-09-12T10:00:00Z GET /b 200 5\nbad\n", within: 1.minute) is Ok(_)
  assert fs.write("d/a.log", "2026-09-12T10:00:00Z GET /a 200 5\n", within: 1.minute) is Ok(_)
  assert fs.write("d/notes.txt", "2026-09-12T10:00:00Z GET /t 200 9\n", within: 1.minute) is Ok(_)
  assert fs.write("d/old.log/c.log", "2026-09-12T10:00:00Z GET /c 200 9\n",
    within: 1.minute) is Ok(_)
  assert fs.write("e.log", "2026-09-12T10:00:00Z GET /e 200 9\n", within: 1.minute) is Ok(_)
  assert ran(fs, ["d", "--top", "1", "--json"]) is Ok(report)
  assert report.starts_with?("{\"requests\": 2, \"errors\": 0, \"error_rate\": 0.0, \"malformed\": 1,")
  assert report.contains?("\"slowest\": [{\"ms\": 5, \"method\": \"GET\", \"path\": \"/a\"")
  assert ran(fs, ["d"]) is Ok(text)
  assert text.starts_with?("requests     2\n")
end

test "a folder with no .log file, or no folder there, exits 1"
  fs = Fs.fixture()
  assert fs.write("d/notes.txt", "2026-09-12T10:00:00Z GET /t 200 9\n", within: 1.minute) is Ok(_)
  assert ran(fs, ["d"]) == Error(NoLogs(dir: "d"))
  assert ran(fs, ["nowhere"]) == Error(NoLogs(dir: "nowhere"))
  assert code_of(NoLogs(dir: "d")) == 1
  assert said(NoLogs(dir: "d")) == "no .log file in d"
end

test "bytes split into lines as text does, and a line that is not UTF-8 is malformed"
  assert byte_lines([]) == []
  assert byte_lines([97, 10, 98, 13, 10, 10, 99]) == [[97], [98], [], [99]]
  assert byte_lines([97, 10]) == [[97]]
  good = "2026-09-12T10:00:00Z GET /a 200 5".bytes
  summary = byte_lines(good.concat([10, 255, 10]).concat(good)).reduce(empty(5, None),
    fn(s, line) counted_bytes(s, line) end)
  assert summary.requests == 2 and summary.malformed == 1
end

test rejects "a name that leaves the folder"
  folded(Fs.fixture().read_only, "../secret.log", empty(5, None))
end

verified: types, contracts, tests (6), property (0 seeds), sim (not run)
          proven: not run
