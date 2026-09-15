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
  # body gone; regenerate
end

fn analyze(fs: Fs, args: List(String)) : Result(String, Problem)
  # body gone; regenerate
end

# The .log files directly inside the directory, in name order; a directory with none, or
# none to list, is NoLogs.
fn log_names(logs: Fs, dir: String) : Result(List(String), Problem)
  # body gone; regenerate
end

fn logged(names: List(String)) : List(String)
  ensures result.size <= names.size
  # body gone; regenerate
end

fn read_log(logs: Fs, name: String) : Result(List(String), Problem)
  # body gone; regenerate
end

fn options(args: List(String)) : Result(Options, Problem)
  ensures result is Ok(o) implies o.dir != ""
  # body gone; regenerate
end

# One argument read: the options so far, and the flag still waiting for its value, or "".
fn step(parsed: Options, pending: String, arg: String) : Result((Options, String), Problem)
  # body gone; regenerate
end

fn top_of(arg: String) : Result(UInt64, Problem)
  ensures result is Ok(n) implies n >= 1 and n <= 100
  # body gone; regenerate
end

fn since_of(arg: String) : Result(Time, Problem)
  # body gone; regenerate
end

fn tally_lines(tally: Tally, lines: List(String)) : Tally
  # body gone; regenerate
end

# A blank line is skipped; a line that does not parse is counted as malformed.
fn tally_line(tally: Tally, line: String) : Tally
  requires !line.contains?("\n")
  # body gone; regenerate
end

fn main(platform: Platform)
  # body gone; regenerate
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
