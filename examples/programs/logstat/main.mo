# run: fixture
# run: fixture --json --top 3
# run: --top 2 fixture --since 2026-09-12T10:01:00Z
# run: fixture --top 0
# exit: 2
# run: .
# exit: 1
module Logstat.Main
expose Options, Problem, options, report, main

use Logstat.Report{json, text}
use Logstat.Stats{Summary, Window, empty, with_lines}

intent "Run logstat: read every `*.log` file directly inside one folder, in name order, one file at a time, through a read-only Fs scoped to that folder, and print the text report or the JSON form; a usage error exits 2 and a folder with no .log file exits 1."

struct Options
  dir: String
  window: Window
  json: Bool
end

enum Problem
  Usage(detail: String)
  NoLogs(dir: String)
  Unread(name: String)
end

# The arguments as seen so far: each flag at most once, the folder exactly once.
struct Given
  dir: Option(String)
  top: Option(UInt64)
  since: Option(Time)
  json: Bool
end

fn options(args: List(String)) : Result(Options, Problem)
  ensures result is Ok(o) implies o.window.top >= 1 and o.window.top <= 100

  nothing = Given(dir: None, top: None, since: None, json: false)
  seen = try given(args, nothing)
  case seen.dir
    Some(dir):
      Ok(Options(dir: dir, window: Window(top: seen.top or 5, since: seen.since), json: seen.json))
    None: Error(Usage(detail: "no folder given"))
  end
end

fn given(args: List(String), seen: Given) : Result(Given, Problem)
  return Ok(seen) if args.size == 0
  word = args.first or ""
  value = args.get(1)
  case word
    "--json":
      next = try with_json(seen)
      given(args.drop(1), next)
    "--top":
      next = try with_top(seen, value)
      given(args.drop(2), next)
    "--since":
      next = try with_since(seen, value)
      given(args.drop(2), next)
    _:
      next = try with_dir(seen, word)
      given(args.drop(1), next)
  end
end

fn with_json(seen: Given) : Result(Given, Problem)
  return Error(Usage(detail: "--json is given twice")) if seen.json
  var next = seen
  next.json = true
  Ok(next)
end

fn with_top(seen: Given, value: Option(String)) : Result(Given, Problem)
  return Error(Usage(detail: "--top is given twice")) if seen.top is Some(_)
  n = try top_of(value or "")
  var next = seen
  next.top = Some(n)
  Ok(next)
end

# 1 to 100; anything else is a usage error, never clamped.
fn top_of(text: String) : Result(UInt64, Problem)
  ensures result is Ok(n) implies n >= 1 and n <= 100

  case text.to_u64
    Some(n) if n >= 1 and n <= 100: Ok(n)
    Some(_): Error(bad_top(text))
    None: Error(bad_top(text))
  end
end

fn bad_top(text: String) : Problem
  Usage(detail: "--top takes a number from 1 to 100, not \"#{text}\"")
end

fn with_since(seen: Given, value: Option(String)) : Result(Given, Problem)
  return Error(Usage(detail: "--since is given twice")) if seen.since is Some(_)
  text = value or ""
  case Time.parse(text)
    Some(t):
      var next = seen
      next.since = Some(t)
      Ok(next)
    None: Error(Usage(detail: "--since takes an ISO-8601 instant, not \"#{text}\""))
  end
end

fn with_dir(seen: Given, word: String) : Result(Given, Problem)
  return Error(Usage(detail: "unknown flag #{word}")) if word.starts_with?("-")
  return Error(Usage(detail: "one folder only, not #{word} too")) if seen.dir is Some(_)
  var next = seen
  next.dir = Some(word)
  Ok(next)
end

# The report for the arguments, reading only inside the folder they name.
fn report(fs: Fs, args: List(String)) : Result(String, Problem)
  given = try options(args)
  logs = fs.scoped(given.dir).read_only
  summary = try summary_of(logs, given.dir, given.window)
  return Ok(json(summary, given.window.top)) if given.json
  Ok(text(summary, given.window.top))
end

# One file at a time: only one file's lines are held at once.
fn summary_of(logs: Fs, dir: String, window: Window) : Result(Summary, Problem)
  names = try log_names(logs, dir)
  var summary = empty()
  for name in names
    case logs.read_lines(name, within: 10.minute)
      Ok(lines):
        summary = with_lines(summary, lines, window)
      Error(_):
        return Error(Unread(name: name))
    end
  end
  Ok(summary)
end

fn log_names(logs: Fs, dir: String) : Result(List(String), Problem)
  ensures result is Ok(names) implies names.size > 0

  case logs.list(within: 1.minute)
    Ok(names): some_logs(names.filter(fn(name) name.ends_with?(".log") end).sort, dir)
    Error(_): Error(NoLogs(dir: dir))
  end
end

fn some_logs(names: List(String), dir: String) : Result(List(String), Problem)
  return Error(NoLogs(dir: dir)) if names.size == 0
  Ok(names)
end

fn said(problem: Problem) : String
  case problem
    Usage(detail): "#{detail}; usage: logstat <dir> [--top N] [--since <ISO-8601>] [--json]"
    NoLogs(dir): "no .log file in #{dir}"
    Unread(name): "cannot read #{name}"
  end
end

fn code(problem: Problem) : UInt8
  case problem
    Usage(_): 2
    NoLogs(_): 1
    Unread(_): 1
  end
end

fn main(platform: Platform)
  case report(platform.fs, platform.args)
    Ok(output): platform.stdout.write(output)
    Error(problem):
      platform.stderr.write_line("logstat: #{said(problem)}")
      platform.exit(code(problem))
  end
end

# Two logs and a text file in logs/, and a log beside logs/ that a report on logs/ must not read.
fn filled(fs: Fs) : Bool
  a = fs.write("logs/b.log", "2026-09-12T10:00:00Z GET /a 200 5\nnot a line\n", within: 1.minute)
  b = fs.write("logs/a.log", "2026-09-12T10:02:00Z POST /b 503 90\n", within: 1.minute)
  c = fs.write("logs/notes.txt", "2026-09-12T10:01:00Z GET /c 200 1\n", within: 1.minute)
  d = fs.write("secret.log", "2026-09-12T10:01:00Z GET /secret 200 1\n", within: 1.minute)
  a is Ok(_) and b is Ok(_) and c is Ok(_) and d is Ok(_)
end

test "a folder alone takes the defaults: top 5, no since, the text report"
  assert options(["logs"]) is Ok(o)
  assert o.dir == "logs" and o.window.top == 5 and o.window.since is None and !o.json
end

test "flags come in any order around the folder"
  assert options(["--json", "--top", "100", "logs", "--since", "2026-09-12T10:01:00Z"]) is Ok(o)
  assert o.dir == "logs" and o.window.top == 100 and o.json
  assert o.window.since == Some(Time.from_parts(2026, 9, 12, 10, 1, 0))
  assert options(["logs", "--top", "1"]) is Ok(_)
end

test "a top outside 1 to 100 is a usage error, not a clamp"
  assert options(["logs", "--top", "0"]) is Error(Usage(_))
  assert options(["logs", "--top", "101"]) is Error(Usage(_))
  assert options(["logs", "--top", "-3"]) is Error(Usage(_))
  assert options(["logs", "--top", "ten"]) is Error(Usage(_))
  assert options(["logs", "--top"]) is Error(Usage(_))
end

test "anything else malformed in the arguments is a usage error"
  assert options([]) is Error(Usage("no folder given"))
  assert options(["--json"]) is Error(Usage(_))
  assert options(["a", "b"]) is Error(Usage(_))
  assert options(["logs", "--verbose"]) is Error(Usage("unknown flag --verbose"))
  assert options(["logs", "--json", "--json"]) is Error(Usage(_))
  assert options(["logs", "--top", "3", "--top", "4"]) is Error(Usage(_))
  assert options(["logs", "--since", "yesterday"]) is Error(Usage(_))
  assert options(["logs", "--since"]) is Error(Usage(_))
end

test "a usage error exits 2 on one line, and a folder with no .log file exits 1"
  assert code(Usage(detail: "no folder given")) == 2
  assert code(NoLogs(dir: "x")) == 1
  assert code(Unread(name: "x.log")) == 1
  assert !said(Usage(detail: "no folder given")).contains?("\n")
  fs = Fs.fixture()
  assert filled(fs)
  assert report(fs, ["nowhere"]) is Error(NoLogs("nowhere"))
  assert report(fs, ["logs/a.log", "--json"]) is Error(NoLogs(_))
end

test "the report reads the .log files in the folder in name order, and nothing outside it"
  fs = Fs.fixture()
  assert filled(fs)
  assert report(fs, ["logs", "--top", "1"]) is Ok(out)
  assert out.starts_with?("requests       2\nerrors         1  (50.0%)\nmalformed      1\n")
  assert out.contains?("slowest\n  90 ms  POST /b   2026-09-12T10:02:00Z\n")
  assert !out.contains?("/secret") and !out.contains?("/c ")
end

test "the JSON form is the report's one line"
  fs = Fs.fixture()
  assert filled(fs)
  assert report(fs, ["logs", "--json"]) is Ok(out)
  assert out.starts_with?("{\"requests\": 2, \"errors\": 1, \"error_rate\": 0.5, \"malformed\": 1, ")
  assert out.lines.size == 1
end

verified: types, contracts, tests (7), property (0 seeds), sim (not run)
          proven: not run
