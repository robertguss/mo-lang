# run: fixture
# run: fixture --top 3 --since 2026-09-12T10:00:10Z --json
# run: fixture --top 0
# exit: 2
# run: .
# exit: 1
module Logstat.Main
expose Options, Problem, options, analyze, main

use Logstat.Parse{parse_line}
use Logstat.Report{json, text}
use Logstat.Stats{Tally, Top, add, add_malformed, start, summarize}

intent "Summarize every .log file directly inside a directory, one file at a time, as text or JSON; a usage error exits 2 and no log file exits 1."

struct Options
  dir: String
  top: Top
  since: Option(Time)
  json: Bool
end

enum Problem
  Usage(detail: String)
  NoLogs(dir: String)
  Unread(name: String)
  Slow(name: String)
end

fn usage() : String
  "usage: logstat <dir> [--top N] [--since <ISO-8601>] [--json]"
end

fn analyze(fs: Fs, args: List(String)) : Result(String, Problem)
  parsed = try options(args)
  logs = fs.scoped(parsed.dir).read_only
  names = try log_names(logs, parsed.dir)
  var tally = start(parsed.top, parsed.since)
  for name in names
    lines = try read_log(logs, name)
    tally = tally_lines(tally, lines)
  end
  summary = summarize(tally)
  Ok(if parsed.json: json(summary) else: text(summary))
end

# The .log files directly inside the directory, in name order; a directory with none, or
# none to list, is NoLogs.
fn log_names(logs: Fs, dir: String) : Result(List(String), Problem)
  case logs.list(within: 10.seconds)
    Ok(names):
      kept = logged(names)
      if kept.size == 0: Error(NoLogs(dir: dir)) else: Ok(kept)
    Error(Timeout): Error(Slow(name: dir))
    Error(Missing(_)): Error(NoLogs(dir: dir))
    Error(NotText): Error(NoLogs(dir: dir))
  end
end

fn logged(names: List(String)) : List(String)
  ensures result.size <= names.size

  names.filter(fn(name) name.size > 4 and name.ends_with?(".log") end).sort
end

fn read_log(logs: Fs, name: String) : Result(List(String), Problem)
  case logs.read_lines(name, within: 30.seconds)
    Ok(lines): Ok(lines)
    Error(Timeout): Error(Slow(name: name))
    Error(Missing(_)): Error(Unread(name: name))
    Error(NotText): Error(Unread(name: name))
  end
end

fn options(args: List(String)) : Result(Options, Problem)
  ensures result is Ok(o) implies o.dir != ""

  var parsed = Options(dir: "", top: 5, since: None, json: false)
  var pending = ""
  for arg in args
    taken = try step(parsed, pending, arg)
    parsed = taken.0
    pending = taken.1
  end
  return Error(Usage(detail: "#{pending} takes a value")) if pending != ""
  return Error(Usage(detail: "a directory to read is required")) if parsed.dir == ""
  Ok(parsed)
end

# One argument read: the options so far, and the flag still waiting for its value, or "".
fn step(parsed: Options, pending: String, arg: String) : Result((Options, String), Problem)
  var next = parsed
  if pending == "--top"
    chosen = try top_of(arg)
    next.top = chosen
    return Ok((next, ""))
  end
  if pending == "--since"
    at = try since_of(arg)
    next.since = Some(at)
    return Ok((next, ""))
  end
  return Ok((next, arg)) if arg == "--top" or arg == "--since"
  if arg == "--json"
    next.json = true
    return Ok((next, ""))
  end
  return Error(Usage(detail: "#{arg} is not a flag logstat knows")) if arg.starts_with?("--")
  return Error(Usage(detail: "one directory at a time, so #{arg} is one too many")) if next.dir != ""
  next.dir = arg
  Ok((next, ""))
end

fn top_of(arg: String) : Result(UInt64, Problem)
  ensures result is Ok(n) implies n >= 1 and n <= 100

  case arg.to_u64
    Some(n) if n >= 1 and n <= 100: Ok(n)
    Some(_): Error(Usage(detail: "--top is 1 to 100, not #{arg}"))
    None: Error(Usage(detail: "--top takes a number, not #{arg}"))
  end
end

fn since_of(arg: String) : Result(Time, Problem)
  case Time.parse(arg)
    Some(at): Ok(at)
    None: Error(Usage(detail: "--since takes an ISO-8601 time, not #{arg}"))
  end
end

fn tally_lines(tally: Tally, lines: List(String)) : Tally
  lines.reduce(tally, fn(so_far, line) tally_line(so_far, line) end)
end

# A blank line is skipped; a line that does not parse is counted as malformed.
fn tally_line(tally: Tally, line: String) : Tally
  requires !line.contains?("\n")

  text = line.trim
  return tally if text == ""
  case parse_line(text)
    Ok(record): add(tally, record)
    Error(_): add_malformed(tally)
  end
end

fn main(platform: Platform)
  case analyze(platform.fs, platform.args)
    Ok(report): platform.stdout.write(report)
    Error(Usage(detail)):
      platform.stderr.write("#{detail}; #{usage()}\n")
      platform.exit(2)
    Error(NoLogs(dir)):
      platform.stderr.write("there is no .log file in #{dir}\n")
      platform.exit(1)
    Error(Unread(name)):
      platform.stderr.write("#{name} could not be read\n")
      platform.exit(1)
    Error(Slow(name)):
      platform.stderr.write("#{name} took longer to read than logstat waits\n")
      platform.exit(1)
  end
end

test "the defaults are the top five, no since, and text"
  assert options(["logs"]) is Ok(parsed)
  assert parsed.dir == "logs"
  assert parsed.top == 5
  assert parsed.since is None
  assert !parsed.json
end

test "flags may come in any order around the directory"
  args = ["--json", "logs", "--top", "3", "--since", "2026-09-12T10:00:00Z"]
  assert options(args) is Ok(parsed)
  assert parsed.dir == "logs"
  assert parsed.top == 3
  assert parsed.json
  assert parsed.since == Time.parse("2026-09-12T10:00:00Z")
end

test "a top outside 1 to 100 is a usage error, not a clamp"
  assert options(["logs", "--top", "0"]) is Error(Usage(_))
  assert options(["logs", "--top", "101"]) is Error(Usage(_))
  assert options(["logs", "--top", "ten"]) is Error(Usage(_))
  assert options(["logs", "--top", "1"]) is Ok(_)
  assert options(["logs", "--top", "100"]) is Ok(_)
end

test "a bad since, an unknown flag, a flag with no value, and one directory too many or too few"
  assert options(["logs", "--since", "yesterday"]) is Error(Usage(_))
  assert options(["logs", "--verbose"]) is Error(Usage(_))
  assert options(["logs", "--top"]) is Error(Usage(_))
  assert options(["logs", "more"]) is Error(Usage(_))
  assert options([]) is Error(Usage(_))
end

test "only names ending in .log are read, in name order"
  assert logged(["b.log", "notes.txt", "a.log", ".log", "c.logs"]) == ["a.log", "b.log"]
end

test "a file folds line by line past a CRLF, a blank line, and a malformed line"
  lines = "2026-09-12T10:00:00Z GET /a 200 5\r\n\nnot a line\n2026-09-12T10:01:00Z GET /a 503 7".lines
  summary = summarize(tally_lines(start(5, None), lines))
  assert summary.requests == 2
  assert summary.errors == 1
  assert summary.malformed == 1
  assert summary.per_minute == 2.0
end

test "no log file, a slow directory, and a usage error each end the run with their problem"
  assert analyze(Fs.fixture(), ["logs"]) is Error(NoLogs("logs"))
  assert analyze(Fs.fixture(delay: 1.minute), ["logs"]) is Error(Slow("logs"))
  assert analyze(Fs.fixture(), ["logs", "--top", "0"]) is Error(Usage(_))
end

test rejects "a line handed to the tally with its newline"
  tally_line(start(5, None), "a\nb")
end

verified: types, contracts, tests (8), property (0 seeds), sim (not run)
          proven: not run
