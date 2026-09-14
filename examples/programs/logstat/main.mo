# run: fixture
# run: fixture --json --top 3
# run: --top 2 fixture --since 2026-09-12T10:01:00Z
# run: fixture --top 101
# exit: 2
# run: .
# exit: 1
module Logstat.Main
expose Options, Problem, options_of, summarized_in, said, code_of, main

use Logstat.Report{json_of, text_of}
use Logstat.Stats{Tally, Top, counted_line, fresh, summary_of}

intent "Run logstat: read every .log file directly inside the folder it is given, in name order, one file at a time and one line at a time, through a read-only Fs scoped to that folder, and print the summary as text or JSON; a usage error exits 2 with one line on stderr, and a folder with no .log file exits 1."

struct Options
  dir: String
  top: Top
  since: Option(Time)
  json: Bool
end

# The options read so far, before a folder and a top are settled.
struct Draft
  dir: Option(String)
  top: Option(Top)
  since: Option(Time)
  json: Bool
end

enum Problem
  Usage(detail: String)
  NoLogs(dir: String)
  Unlisted(dir: String)
  Slow(name: String)
  Binary(name: String)
end

fn usage() : String
  "usage: logstat <dir> [--top N] [--since <ISO-8601>] [--json]"
end

# The folder and the options, in any order; --top N outside 1 to 100 is a usage error, never
# clamped.
fn options_of(args: List(String)) : Result(Options, Problem)
  ensures result is Ok(o) implies o.top >= 1 and o.top <= 100

  draft = try drafted(Draft(dir: None, top: None, since: None, json: false), args)
  case draft.dir
    Some(dir): Ok(Options(dir: dir, top: draft.top or 5, since: draft.since, json: draft.json))
    None: Error(Usage(detail: "no folder given"))
  end
end

fn drafted(draft: Draft, args: List(String)) : Result(Draft, Problem)
  return Ok(draft) if args.size == 0
  word = args.first or ""
  value = args.get(1) or ""
  case word
    "--json": drafted(try with_json(draft), args.drop(1))
    "--top": drafted(try with_top(draft, value), args.drop(2))
    "--since": drafted(try with_since(draft, value), args.drop(2))
    _: drafted(try with_dir(draft, word), args.drop(1))
  end
end

fn with_json(draft: Draft) : Result(Draft, Problem)
  return Error(Usage(detail: "--json given twice")) if draft.json
  var next = draft
  next.json = true
  Ok(next)
end

fn with_top(draft: Draft, text: String) : Result(Draft, Problem)
  return Error(Usage(detail: "--top given twice")) if draft.top is Some(_)
  n = text.to_u64 or 0
  return Error(Usage(detail: "--top takes a number from 1 to 100")) if n < 1 or n > 100
  var next = draft
  next.top = Some(n)
  Ok(next)
end

fn with_since(draft: Draft, text: String) : Result(Draft, Problem)
  return Error(Usage(detail: "--since given twice")) if draft.since is Some(_)
  case Time.parse(text)
    Some(t):
      var next = draft
      next.since = Some(t)
      Ok(next)
    None: Error(Usage(detail: "--since takes an ISO-8601 time such as 2026-09-12T10:00:00Z"))
  end
end

fn with_dir(draft: Draft, word: String) : Result(Draft, Problem)
  return Error(Usage(detail: "no option #{word}")) if word.starts_with?("--")
  return Error(Usage(detail: "one folder only")) if draft.dir is Some(_)
  var next = draft
  next.dir = Some(word)
  Ok(next)
end

# logs is the folder already, scoped and read-only; nothing outside it can be named through it.
fn summarized_in(logs: Fs, options: Options) : Result(String, Problem)
  names = try log_names(logs, options.dir)
  var tally = fresh()
  for name in names
    tally = try folded(logs, name, tally, options)
  end
  summary = summary_of(tally, options.top)
  return Ok(json_of(summary)) if options.json
  Ok(text_of(summary))
end

# The names ending in .log, in name order as list gives them.
fn log_names(logs: Fs, dir: String) : Result(List(String), Problem)
  case logs.list(within: 1.minute)
    Ok(names): logs_among(names, dir)
    Error(_): Error(Unlisted(dir: dir))
  end
end

fn logs_among(names: List(String), dir: String) : Result(List(String), Problem)
  found = names.filter(fn(name) name.ends_with?(".log") end)
  return Error(NoLogs(dir: dir)) if found.size == 0
  Ok(found)
end

# One file folded into the tally a line at a time, so no more than a line of it is held. A name
# that lists but does not read as a file, a folder named like a log, is passed over.
fn folded(logs: Fs, name: String, tally: Tally, options: Options) : Result(Tally, Problem)
  since = options.since
  top = options.top
  read = logs.fold_lines(name, tally, within: 60.minute,
    fn(so_far, line) counted_line(so_far, line, since, top) end)
  case read
    Ok(next): Ok(next)
    Error(Missing(_)): Ok(tally)
    Error(Timeout): Error(Slow(name: name))
    Error(NotText): Error(Binary(name: name))
  end
end

fn said(problem: Problem) : String
  case problem
    Usage(detail): "#{detail}; #{usage()}"
    NoLogs(dir): "no .log file in #{dir}"
    Unlisted(dir): "cannot list the folder #{dir}"
    Slow(name): "reading #{name} took longer than an hour"
    Binary(name): "#{name} is not UTF-8 text"
  end
end

fn code_of(problem: Problem) : UInt8
  case problem
    Usage(_): 2
    NoLogs(_) | Unlisted(_) | Slow(_) | Binary(_): 1
  end
end

fn run(fs: Fs, args: List(String)) : Result(String, Problem)
  options = try options_of(args)
  summarized_in(fs.scoped(options.dir).read_only, options)
end

fn main(platform: Platform)
  case run(platform.fs, platform.args)
    Ok(text): platform.stdout.write(text)
    Error(problem):
      platform.stderr.write_line("logstat: #{said(problem)}")
      platform.exit(code_of(problem))
  end
end

fn options(dir: String, top: Top, json: Bool) : Options
  Options(dir: dir, top: top, since: None, json: json)
end

# Fills an Fs with a logs folder of two logs and a note, and a log outside it; true when every
# write went through.
fn filled(fs: Fs) : Bool
  made = fs.mkdir("logs", within: 1.minute) is Ok(_)
  b = fs.write("logs/b.log", "2026-09-12T10:00:00Z GET /b 200 7\nbad\n", within: 1.minute)
  a = fs.write("logs/a.log", "2026-09-12T10:00:00Z GET /a 500 7\n", within: 1.minute)
  note = fs.write("logs/notes.txt", "2026-09-12T10:00:00Z GET /n 200 9\n", within: 1.minute)
  outside = fs.write("outside.log", "2026-09-12T10:00:00Z GET /out 200 9\n", within: 1.minute)
  made and b is Ok(_) and a is Ok(_) and note is Ok(_) and outside is Ok(_)
end

test "a folder and the options come in any order, with a top of 5 by default"
  assert options_of(["logs"]) == Ok(options("logs", 5, false))
  assert options_of(["--json", "logs", "--top", "100"]) == Ok(options("logs", 100, true))
  assert options_of(["--since", "2026-09-12T10:00:00Z", "logs"]) is Ok(o)
  assert o.since == Some(Time.from_parts(2026, 9, 12, 10, 0, 0)) and o.top == 5
end

test "a top outside 1 to 100, a missing or second folder, or an unknown or repeated option is a usage error"
  assert options_of(["logs", "--top", "0"]) is Error(Usage(_))
  assert options_of(["logs", "--top", "101"]) is Error(Usage(_))
  assert options_of(["logs", "--top", "five"]) is Error(Usage(_))
  assert options_of(["logs", "--top"]) is Error(Usage(_))
  assert options_of(["logs", "--since", "yesterday"]) is Error(Usage(_))
  assert options_of([]) is Error(Usage(_))
  assert options_of(["--json"]) is Error(Usage(_))
  assert options_of(["logs", "more"]) is Error(Usage(_))
  assert options_of(["logs", "--verbose"]) is Error(Usage(_))
  assert options_of(["logs", "--json", "--json"]) is Error(Usage(_))
  assert options_of(["logs", "--top", "3", "--top", "4"]) is Error(Usage(_))
end

test "the .log files inside the folder are read in name order, and nothing outside it"
  fs = Fs.fixture()
  assert filled(fs)
  logs = fs.scoped("logs").read_only
  assert summarized_in(logs, options("logs", 5, false)) is Ok(text)
  assert text.lines.take(3) == ["requests       2", "errors         1  (50.0%)", "malformed      1"]
  assert text.lines.slice(6, 8) == ["  7 ms  GET /a   2026-09-12T10:00:00Z",
    "  7 ms  GET /b   2026-09-12T10:00:00Z"]
  assert !text.contains?("/out") and !text.contains?("/n ")
  assert summarized_in(fs.scoped("logs").scoped("..").read_only,
    options("..", 5, false)) is Error(Unlisted(".."))
end

test "the JSON form is chosen by --json"
  fs = Fs.fixture()
  assert filled(fs)
  logs = fs.scoped("logs").read_only
  assert summarized_in(logs, options("logs", 1, true)) is Ok(json)
  assert json.starts_with?("{\"requests\": 2, \"errors\": 1, \"error_rate\": 0.500, \"malformed\": 1,")
end

test "a usage error exits 2, and a folder with no .log file or that cannot be read exits 1"
  assert summarized_in(Fs.fixture(), options(".", 5, false)) is Error(NoLogs("."))
  assert summarized_in(Fs.fixture(delay: 2.minute), options(".", 5, false)) is Error(Unlisted("."))
  assert code_of(Usage(detail: "no folder given")) == 2
  assert code_of(NoLogs(dir: ".")) == 1 and code_of(Unlisted(dir: ".")) == 1
  assert code_of(Slow(name: "a.log")) == 1 and code_of(Binary(name: "a.log")) == 1
  assert said(Usage(detail: "one folder only")) == "one folder only; usage: logstat <dir> [--top N] [--since <ISO-8601>] [--json]"
end

verified: types, contracts, tests (5), property (0 seeds), sim (not run)
          proven: not run
