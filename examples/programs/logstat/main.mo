# run: fixture a.log b.log c.log notes.txt
module Logstat.Main
expose Options, Problem, options, analyze, main

use Logstat.Parse{digits?, number, parse_bytes, slice, timestamp}
use Logstat.Report{json, text}
use Logstat.Stats{Tally, Top, add, add_malformed, start, summarize}

intent "Summarize the .log files named in a directory, one file at a time, as text or JSON; a usage error exits 2 and no log file exits 1."

struct Options
  dir: String
  names: List(String)
  top: Top
  since: UInt64
  json: Bool
end

enum Problem
  Usage(detail: String)
  NoLogs(dir: String)
  Unread(name: String)
  Slow(name: String)
end

fn usage() : String
  "usage: logstat <dir> <name.log>... [--top N] [--since <ISO-8601>] [--json]"
end

fn analyze(fs: Fs, args: List(String)) : Result(String, Problem)
  parsed = try options(args)
  logs = fs.scoped(parsed.dir).read_only
  names = log_names(parsed.names)
  return Error(NoLogs(dir: parsed.dir)) if names.size == 0
  var tally = start(parsed.top, parsed.since)
  for name in names
    contents = try read_log(logs, name)
    tally = tally_text(tally, contents)
  end
  summary = summarize(tally)
  return Ok(json(summary)) if parsed.json
  Ok(text(summary))
end

fn read_log(logs: Fs, name: String) : Result(String, Problem)
  case logs.read(name, within: 10_000.ms)
    Ok(contents): Ok(contents)
    Error(Missing(path)): Error(Unread(name: path))
    Error(Timeout): Error(Slow(name: name))
  end
end

fn options(args: List(String)) : Result(Options, Problem)
  ensures result is Ok(o) implies o.dir != ""

  var parsed = Options(dir: "", names: [], top: 5, since: 0, json: false)
  var pending = ""
  for arg in args
    next = try step(parsed, pending, arg)
    parsed = next.0
    pending = next.1
  end
  return Error(Usage(detail: "#{pending} needs a value")) if pending != ""
  return Error(Usage(detail: "no directory given")) if parsed.dir == ""
  Ok(parsed)
end

# One argument read: the options so far, and the flag still waiting for its value, or "".
fn step(parsed: Options, pending: String, arg: String) : Result((Options, String), Problem)
  var next = parsed
  if pending == "--top"
    next.top = try top_of(arg)
    return Ok((next, ""))
  end
  if pending == "--since"
    next.since = try since_of(arg)
    return Ok((next, ""))
  end
  return Ok((next, arg)) if arg == "--top" or arg == "--since"
  if arg == "--json"
    next.json = true
    return Ok((next, ""))
  end
  return Error(Usage(detail: "unknown option #{arg}")) if arg.starts_with?("-")
  if parsed.dir == ""
    next.dir = arg
  else
    next.names = parsed.names.push(arg)
  end
  Ok((next, ""))
end

fn top_of(arg: String) : Result(UInt64, Problem)
  ensures result is Ok(n) implies n >= 1 and n <= 100

  bad = Error(Usage(detail: "--top takes a whole number from 1 to 100, not #{arg}"))
  bytes = arg.bytes
  return bad if !digits?(bytes) or bytes.size > 3
  n = number(bytes)
  return bad if n < 1 or n > 100
  Ok(n)
end

fn since_of(arg: String) : Result(UInt64, Problem)
  case timestamp(arg.bytes)
    Some(seconds): Ok(seconds)
    None: Error(Usage(detail: "--since takes a time like 2026-09-12T10:00:00Z, not #{arg}"))
  end
end

# Fs cannot list a directory, so the names come from the command line (a shell's *.log).
fn log_names(names: List(String)) : List(String)
  ensures result.size <= names.size

  logs = names.filter(fn(name) log_name?(name) end)
  logs.reduce([], fn(sorted, name) name_inserted(sorted, name) end)
end

fn log_name?(name: String) : Bool
  bytes = name.bytes
  return false if bytes.size <= 4 or bytes.contains?(47)
  slice(bytes, bytes.size - 4, bytes.size) == ".log".bytes
end

fn name_inserted(sorted: List(String), name: String) : List(String)
  ensures result.size == sorted.size + 1

  placed = sorted.reduce(([], false), fn(acc, kept)
    if !acc.1 and name < kept
      (acc.0.push(name).push(kept), true)
    else
      (acc.0.push(kept), acc.1)
    end
  end)
  return placed.0 if placed.1
  placed.0.push(name)
end

# A file is folded a line at a time into the tally; no list of its lines is ever built.
fn tally_text(tally: Tally, contents: String) : Tally
  ended = contents.bytes.reduce((tally, []), fn(acc, b)
    if b == 10
      (tally_line(acc.0, acc.1), [])
    else
      (acc.0, acc.1.push(b))
    end
  end)
  tally_line(ended.0, ended.1)
end

# A blank line is skipped; a line that does not parse is counted as malformed.
fn tally_line(tally: Tally, line: List(UInt8)) : Tally
  requires !line.contains?(10)

  bytes = if line.last == Some(13)
    slice(line, 0, line.size - 1)
  else
    line
  end
  return tally if bytes.size == 0
  case parse_bytes(bytes)
    Ok(record): add(tally, record)
    Error(_): add_malformed(tally)
  end
end

fn main(platform: Platform)
  case analyze(platform.fs.read_only, platform.args)
    Ok(report): platform.stdout.write(report)
    Error(Usage(detail)):
      platform.stderr.write("logstat: #{detail}; #{usage()}\n")
      platform.exit(2)
    Error(NoLogs(dir)):
      platform.stderr.write("logstat: no .log file named in #{dir}\n")
      platform.exit(1)
    Error(Unread(name)):
      platform.stderr.write("logstat: cannot read #{name}\n")
      platform.exit(1)
    Error(Slow(name)):
      platform.stderr.write("logstat: reading #{name} took longer than 10 seconds\n")
      platform.exit(1)
  end
end

test "the defaults are the top five, no since, and text"
  assert options(["logs", "a.log"]) is Ok(parsed)
  assert parsed.dir == "logs"
  assert parsed.names == ["a.log"]
  assert parsed.top == 5
  assert parsed.since == 0
  assert !parsed.json
end

test "flags may come in any order after the directory"
  args = ["logs", "--json", "b.log", "--top", "3", "--since", "2026-09-12T10:00:00Z", "a.log"]
  assert options(args) is Ok(parsed)
  assert parsed.names == ["b.log", "a.log"]
  assert parsed.top == 3
  assert parsed.json
  assert parsed.since == (timestamp("2026-09-12T10:00:00Z".bytes) or 0)
end

test "a top outside 1 to 100 is a usage error, not a clamp"
  assert options(["logs", "--top", "0"]) is Error(Usage(_))
  assert options(["logs", "--top", "101"]) is Error(Usage(_))
  assert options(["logs", "--top", "ten"]) is Error(Usage(_))
  assert options(["logs", "--top", "1"]) is Ok(_)
  assert options(["logs", "--top", "100"]) is Ok(_)
end

test "a bad since, an unknown flag, a flag with no value, and no directory are usage errors"
  assert options(["logs", "--since", "yesterday"]) is Error(Usage(_))
  assert options(["logs", "--verbose"]) is Error(Usage(_))
  assert options(["logs", "--top"]) is Error(Usage(_))
  assert options([]) is Error(Usage(_))
end

test "only names ending in .log, directly inside the directory, are read, in name order"
  names = ["b.log", "notes.txt", "a.log", "../c.log", "sub/d.log", ".log"]
  assert log_names(names) == ["a.log", "b.log"]
end

test "a file folds line by line past a CRLF, a blank line, and a malformed line"
  contents = "2026-09-12T10:00:00Z GET /a 200 5\r\n\nnot a line\n2026-09-12T10:01:00Z GET /a 503 7"
  summary = summarize(tally_text(start(5, 0), contents))
  assert summary.requests == 2
  assert summary.errors == 1
  assert summary.malformed == 1
  assert summary.per_minute_tenths == 20
end

test "no log name, a missing file, and a slow read each end the run with their problem"
  assert analyze(Fs.fixture(), ["logs", "notes.txt"]) is Error(NoLogs("logs"))
  assert analyze(Fs.fixture(), ["logs", "a.log"]) is Error(Unread("a.log"))
  assert analyze(Fs.fixture(delay: 1.minute), ["logs", "a.log"]) is Error(Slow("a.log"))
  assert analyze(Fs.fixture(), ["logs", "--top", "0"]) is Error(Usage(_))
end

test rejects "a line handed to the tally with its newline"
  tally_line(start(5, 0), "a\nb".bytes)
end
