# run: fixture
# run: fixture --json --top 3
# run: --top 2 fixture --since 2026-09-12T10:01:04Z
# run: fixture --top 0
# exit: 2
# run: fixture/none
# exit: 1
# run: fixture/nowhere
# exit: 1
module Logstat.Main
expose Options, Problem, options, ran, main

use Logstat.Report{json, shown, text}
use Logstat.Stats{Summary, empty, folded}

intent "Run logstat: read every .log file directly inside the folder it is given, in name order, one file at a time and only through that folder, and print the summary as text or as JSON; a usage error exits 2 and a folder with no .log file to read exits 1."

struct Options
  dir: String
  top: UInt64
  since: Option(Time)
  json: Bool
end

enum Problem
  Usage(detail: String)
  NoLogs(dir: String)
  Unread(file: String, why: String)
end

fn usage() : String
  "usage: logstat <dir> [--top N] [--since <ISO-8601>] [--json]"
end

# One folder and the flags, in any order, each flag at most once.
fn options(args: List(String)) : Result(Options, Problem)
  ensures result is Ok(o) implies o.top >= 1 and o.top <= 100 and o.dir != ""

  parsed(args, Options(dir: "", top: 5, since: None, json: false), Set.new())
end

fn parsed(args: List(String), so_far: Options, seen: Set(String)) : Result(Options, Problem)
  word = args.first or ""
  return Error(Usage(detail: "#{word} is given twice")) if seen.has?(word)
  var next = so_far
  case word
    "":
      return Error(Usage(detail: "no folder given")) if so_far.dir == ""
      return Ok(so_far)
    "--json":
      next.json = true
    "--top":
      next.top = try top_of(args.get(1))
    "--since":
      next.since = Some(try since_of(args.get(1)))
    _:
      return Error(Usage(detail: "unknown flag #{word}")) if word.starts_with?("-")
      return Error(Usage(detail: "one folder only, not #{so_far.dir} and #{word}")) if so_far.dir != ""
      next.dir = word
  end
  taken = if word == "--top" or word == "--since": 2 else: 1
  flags = if word.starts_with?("-"): seen.add(word) else: seen
  parsed(args.drop(taken), next, flags)
end

fn top_of(given: Option(String)) : Result(UInt64, Problem)
  ensures result is Ok(n) implies n >= 1 and n <= 100

  n = (given or "").to_u64 or 0
  return Error(Usage(detail: "--top takes a whole number from 1 to 100")) if n < 1 or n > 100
  Ok(n)
end

fn since_of(given: Option(String)) : Result(Time, Problem)
  case Time.parse(given or "")
    Some(at): Ok(at)
    None: Error(Usage(detail: "--since takes an ISO-8601 time such as 2026-09-12T10:00:00Z"))
  end
end

# The whole run over a file system: the report, or the problem that ends logstat.
fn ran(fs: Fs, args: List(String)) : Result(String, Problem)
  given = try options(args)
  folder = fs.scoped(given.dir).read_only
  names = try logs_in(folder, given.dir)
  summary = try summarized(folder, given.dir, names, empty(given.top, given.since))
  report = shown(summary)
  Ok(if given.json: json(report) else: text(report))
end

# The names of the .log files directly inside the folder, in name order.
fn logs_in(folder: Fs, dir: String) : Result(List(String), Problem)
  ensures result is Ok(names) implies names.size > 0

  case folder.list(within: 10_000.ms)
    Ok(names):
      logs = names.filter(fn(name) name.ends_with?(".log") and name.byte_size > 4 end)
      return Error(NoLogs(dir: dir)) if logs.size == 0
      Ok(logs)
    Error(_): Error(NoLogs(dir: dir))
  end
end

# Each file folded in a line at a time, one after another, the summary carried from each file
# into the next, so no more than one line of a file is held.
fn summarized(folder: Fs, dir: String, names: List(String), start: Summary) : Result(Summary,
  Problem)
  var summary = start
  for name in names
    case folder.fold_lines(name, summary, within: 10.minute, fn(s, line) folded(s, line) end)
      Ok(next):
        summary = next
      Error(Timeout):
        return Error(Unread(file: "#{dir}/#{name}", why: "took longer than 10 minutes"))
      Error(_):
        return Error(Unread(file: "#{dir}/#{name}", why: "cannot be read"))
    end
  end
  Ok(summary)
end

fn said(problem: Problem) : String
  case problem
    Usage(detail): "#{detail}; #{usage()}"
    NoLogs(dir): "no .log file in #{dir}"
    Unread(file: file, why: why): "#{file} #{why}"
  end
end

fn code_of(problem: Problem) : UInt8
  case problem
    Usage(_): 2
    NoLogs(_): 1
    Unread(file: _, why: _): 1
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

test "a folder and the flags in any order, the top 5 and every line by default"
  assert options(["logs"]) == Ok(Options(dir: "logs", top: 5, since: None, json: false))
  since = Time.parse("2026-09-12T10:00:00Z")
  assert options(["--json",
    "--since",
    "2026-09-12T10:00:00Z",
    "logs",
    "--top",
    "100"]) == Ok(Options(dir: "logs", top: 100, since: since, json: true))
  assert options(["logs", "--top", "1"]) is Ok(Options(dir: "logs", top: 1, since: None,
    json: false))
end

test "a top outside 1 to 100 is a usage error, not a clamp"
  assert options(["logs", "--top", "0"]) is Error(Usage(_))
  assert options(["logs", "--top", "101"]) is Error(Usage(_))
  assert options(["logs", "--top", "-3"]) is Error(Usage(_))
  assert options(["logs", "--top"]) is Error(Usage(_))
  assert options(["logs", "--top", "five"]) is Error(Usage(_))
end

test "no folder, two folders, an unknown or repeated flag, or a bad time is a usage error"
  assert options([]) is Error(Usage(_))
  assert options(["--json"]) is Error(Usage(_))
  assert options(["a", "b"]) is Error(Usage(_))
  assert options(["logs", "--csv"]) is Error(Usage(_))
  assert options(["logs", "--json", "--json"]) is Error(Usage(_))
  assert options(["logs", "--top", "3", "--top", "4"]) is Error(Usage(_))
  assert options(["logs", "--since", "yesterday"]) is Error(Usage(_))
  assert options(["logs", "--since"]) is Error(Usage(_))
end

test "a usage error exits 2, and a folder with no .log file to read exits 1"
  assert code_of(Usage(detail: "x")) == 2
  assert code_of(NoLogs(dir: "d")) == 1
  assert code_of(Unread(file: "d/a.log", why: "cannot be read")) == 1
  assert said(NoLogs(dir: "d")) == "no .log file in d"
end

test "only the .log files directly inside the folder are read, in name order"
  fs = Fs.fixture()
  assert fs.write("logs/b.log", "2026-09-12T10:00:01Z GET /from-b 200 7\n",
    within: 1.minute) is Ok(_)
  assert fs.write("logs/a.log", "2026-09-12T10:00:01Z GET /from-a 200 7\nbad\n",
    within: 1.minute) is Ok(_)
  assert fs.write("logs/notes.txt", "2026-09-12T10:00:01Z GET /txt 200 9\n",
    within: 1.minute) is Ok(_)
  assert fs.write("logs/deeper/c.log", "2026-09-12T10:00:01Z GET /deeper 200 9\n",
    within: 1.minute) is Ok(_)
  assert fs.write("outside.log", "2026-09-12T10:00:01Z GET /outside 200 9\n",
    within: 1.minute) is Ok(_)
  assert ran(fs,
    ["logs",
    "--json",
    "--top",
    "1"]) == Ok("{\"requests\": 2, \"errors\": 0, \"error_rate\": 0.000, \"malformed\": 1, \"per_minute\": 0.0, \"slowest\": [{\"ms\": 7, \"method\": \"GET\", \"path\": \"/from-a\", \"at\": \"2026-09-12T10:00:01Z\"}], \"busiest\": [{\"count\": 1, \"method\": \"GET\", \"path\": \"/from-a\"}]}\n")
end

test "a folder that is not there, or holds no .log file, is NoLogs"
  fs = Fs.fixture()
  assert fs.write("quiet/readme.txt", "nothing here\n", within: 1.minute) is Ok(_)
  assert ran(fs, ["quiet"]) == Error(NoLogs(dir: "quiet"))
  assert ran(fs, ["nowhere"]) == Error(NoLogs(dir: "nowhere"))
  assert ran(fs, ["quiet", "--top", "0"]) is Error(Usage(_))
end

verified: types, contracts, tests (6), property (0 seeds), sim (not run)
          proven: not run
