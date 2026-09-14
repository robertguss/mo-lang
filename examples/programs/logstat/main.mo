# run: fixture
# run: fixture --json
# run: --since 2026-09-12T10:01:20Z fixture --top 2
# run: fixture --top 101
# exit: 2
# run: nowhere
# exit: 1
module Logstat.Main
expose Options, Problem, options, log_names, summarize, run, main

use Logstat.Parse{parse}
use Logstat.Report{json, text}
use Logstat.Stats{Summary, Tally, counted, empty, malformed_line, summary}

intent "Run logstat <dir> [--top N] [--since <ISO-8601>] [--json]: read every *.log file directly inside <dir>, in name order and one file at a time, through a read-only Fs scoped to <dir>, so no file outside it is read; print the text report or the JSON object. A usage error exits 2 with one line on stderr, and a folder with no .log file exits 1."

struct Options
  dir: String
  top: UInt64
  since: Option(Time)
  json: Bool
end

enum Problem
  Usage(detail: String)
  NoLogs(dir: String)
  Unreadable(name: String, why: String)
end

fn usage() : String
  "usage: logstat <dir> [--top N] [--since <ISO-8601>] [--json]"
end

# Flags come in any order around the one <dir>, each at most once.
fn options(args: List(String)) : Result(Options, Problem)
  read = try flags(args, Options(dir: "", top: 5, since: None, json: false), [])
  return Error(Usage(detail: "no <dir> given")) if read.dir == ""
  Ok(read)
end

# seen holds each flag given so far, and <dir> once a folder is.
fn flags(rest: List(String), so_far: Options, seen: List(String)) : Result(Options, Problem)
  return Ok(so_far) if rest.size == 0
  word = rest.first or ""
  key = key_of(word)
  return Error(Usage(detail: "#{key} is given twice")) if seen.contains?(key)
  taken = try flag(so_far, word, rest.get(1))
  flags(rest.drop(taken.1), taken.0, seen.push(key))
end

fn key_of(word: String) : String
  return word if word.starts_with?("--")
  "<dir>"
end

# The options with one word, and the value after it for --top and --since, taken; and how many words.
fn flag(o: Options, word: String, value: Option(String)) : Result((Options, UInt64), Problem)
  var next = o
  case word
    "--json":
      next.json = true
      Ok((next, 1))
    "--top":
      next.top = try top_of(value or "")
      Ok((next, 2))
    "--since":
      at = try since_of(value or "")
      next.since = Some(at)
      Ok((next, 2))
    _:
      return Error(Usage(detail: "there is no flag #{word}")) if word.starts_with?("--")
      next.dir = word
      Ok((next, 1))
  end
end

fn top_of(text: String) : Result(UInt64, Problem)
  n = text.to_u64 or 0
  return Error(Usage(detail: "--top takes a whole number from 1 to 100")) if n < 1 or n > 100
  Ok(n)
end

fn since_of(text: String) : Result(Time, Problem)
  case Time.parse(text)
    Some(at): Ok(at)
    None: Error(Usage(detail: "--since takes an ISO-8601 time such as 2026-09-12T10:00:00Z"))
  end
end

# The names a shell's *.log matches, a leading dot excluded, in name order.
fn log_names(names: List(String)) : List(String)
  names.filter(fn(name) name.ends_with?(".log") and !name.starts_with?(".") end).sort
end

# dir is the read-only Fs scoped to <dir>: nothing outside it can be read through it.
fn summarize(dir: Fs, o: Options) : Result(Summary, Problem)
  names = log_names(listed(dir))
  return Error(NoLogs(dir: o.dir)) if names.size == 0
  var tally = empty(o.top)
  for name in names
    tally = try with_file(dir, name, tally, o.since)
  end
  Ok(summary(tally))
end

# A folder that is not there, or cannot be listed, holds no .log file.
fn listed(dir: Fs) : List(String)
  case dir.list(within: 1.minute)
    Ok(names): names
    Error(_): []
  end
end

# One file's lines folded into the tally as the file is read, never the whole file held at once.
fn with_file(dir: Fs, name: String, tally: Tally, since: Option(Time)) : Result(Tally, Problem)
  case dir.fold_lines(name, tally, within: 1.days, fn(t, line) folded(t, line, since) end)
    Ok(after): Ok(after)
    Error(NotText): Error(Unreadable(name: name, why: "is not UTF-8 text"))
    Error(Missing(_)): Error(Unreadable(name: name, why: "cannot be read"))
    Error(Timeout): Error(Unreadable(name: name, why: "took longer than a day to read"))
  end
end

fn folded(t: Tally, line: String, since: Option(Time)) : Tally
  case parse(line)
    Ok(e):
      return t if before?(e.at, since)
      counted(t, e)
    Error(_): malformed_line(t)
  end
end

fn before?(at: Time, since: Option(Time)) : Bool
  case since
    Some(from): at < from
    None: false
  end
end

fn run(fs: Fs, args: List(String)) : Result(String, Problem)
  o = try options(args)
  s = try summarize(fs.scoped(o.dir).read_only, o)
  return Ok("#{json(s)}\n") if o.json
  Ok(text(s))
end

fn said(problem: Problem) : String
  case problem
    Usage(detail): "#{detail}; #{usage()}"
    NoLogs(dir): "no .log file in #{dir}"
    Unreadable(name: name, why: why): "#{name} #{why}"
  end
end

fn code_of(problem: Problem) : UInt8
  case problem
    Usage(_): 2
    NoLogs(_) | Unreadable(name: _, why: _): 1
  end
end

fn main(platform: Platform)
  case run(platform.fs.read_only, platform.args)
    Ok(printed): platform.stdout.write(printed)
    Error(problem):
      platform.stderr.write_line("logstat: #{said(problem)}")
      platform.exit(code_of(problem))
  end
end

test "the one <dir> comes with defaults, and flags in any order set the rest"
  assert options(["logs"]) == Ok(Options(dir: "logs", top: 5, since: None, json: false))
  since = Time.parse("2026-09-12T10:00:00Z")
  assert options(["--json",
    "--top",
    "3",
    "logs",
    "--since",
    "2026-09-12T10:00:00Z"]) == Ok(Options(dir: "logs", top: 3, since: since, json: true))
end

test "--top outside 1 to 100 is a usage error, not a clamp"
  assert options(["logs", "--top", "0"]) is Error(Usage(_))
  assert options(["logs", "--top", "101"]) is Error(Usage(_))
  assert options(["logs", "--top", "1"]) is Ok(_)
  assert options(["logs", "--top", "100"]) is Ok(_)
  assert options(["logs", "--top"]) is Error(Usage(_))
  assert options(["logs", "--top", "five"]) is Error(Usage(_))
end

test "no <dir>, two of them, an unknown flag, a flag twice, or a --since that is not a time is a usage error"
  assert options([]) is Error(Usage(_))
  assert options(["--json"]) is Error(Usage(_))
  assert options(["a", "b"]) is Error(Usage(_))
  assert options(["logs", "--verbose"]) is Error(Usage(_))
  assert options(["logs", "--json", "--json"]) is Error(Usage(_))
  assert options(["logs", "--since", "yesterday"]) is Error(Usage(_))
  assert code_of(Usage(detail: "no <dir> given")) == 2
  assert said(Usage(detail: "no <dir> given")) == "no <dir> given; usage: logstat <dir> [--top N] [--since <ISO-8601>] [--json]"
end

test "only the *.log names are read, in name order"
  assert log_names(["b.log", "notes.txt", "a.log", ".hidden.log", "c.log.gz"]) == ["a.log", "b.log"]
end

test "a folder's logs are read into one summary, and --since leaves out the lines before it"
  fs = Fs.fixture()
  assert fs.mkdir("logs", within: 1.minute) is Ok(_)
  assert fs.write("logs/b.log", "2026-09-12T10:01:00Z GET /b 500 7\nnot a line\n",
    within: 1.minute) is Ok(_)
  assert fs.write("logs/a.log", "2026-09-12T10:00:00Z GET /a 200 9\n", within: 1.minute) is Ok(_)
  assert fs.write("logs/skip.txt", "2026-09-12T10:00:30Z GET /c 200 1\n", within: 1.minute) is Ok(_)
  assert run(fs,
    ["logs"]) == Ok("requests       2\nerrors         1  (50.0%)\nmalformed      1\nper minute   2.0\n\nslowest\n  9 ms  GET /a   2026-09-12T10:00:00Z\n  7 ms  GET /b   2026-09-12T10:01:00Z\n\nbusiest\n  1  GET /a\n  1  GET /b\n")
  assert run(fs,
    ["logs",
    "--since",
    "2026-09-12T10:00:30Z",
    "--json"]) == Ok("{\"requests\": 1, \"errors\": 1, \"error_rate\": 1.0, \"malformed\": 1, \"per_minute\": 0.0, \"slowest\": [{\"ms\": 7, \"method\": \"GET\", \"path\": \"/b\", \"at\": \"2026-09-12T10:01:00Z\"}], \"busiest\": [{\"count\": 1, \"method\": \"GET\", \"path\": \"/b\"}]}\n")
end

test "a folder with no .log file in it, or no folder, exits 1"
  fs = Fs.fixture()
  assert fs.mkdir("empty", within: 1.minute) is Ok(_)
  assert run(fs, ["empty"]) == Error(NoLogs(dir: "empty"))
  assert run(fs, ["nowhere"]) == Error(NoLogs(dir: "nowhere"))
  assert code_of(NoLogs(dir: "nowhere")) == 1
end

test "a .log file above <dir>, or in a folder inside it, is never read"
  fs = Fs.fixture()
  assert fs.mkdir("logs", within: 1.minute) is Ok(_)
  assert fs.mkdir("logs/old", within: 1.minute) is Ok(_)
  assert fs.write("outside.log", "2026-09-12T10:00:00Z GET /a 200 9\n", within: 1.minute) is Ok(_)
  assert fs.write("logs/old/deep.log", "2026-09-12T10:00:00Z GET /a 200 9\n",
    within: 1.minute) is Ok(_)
  assert run(fs, ["logs"]) == Error(NoLogs(dir: "logs"))
end

verified: types, contracts, tests (7), property (0 seeds), sim (not run)
          proven: not run
