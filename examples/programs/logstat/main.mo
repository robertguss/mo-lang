# run: fixture
# run: fixture --top 3 --json
# run: fixture --since 2026-09-12T10:00:45Z --top 2
# run: fixture --top 0
# exit: 2
# run: nologs
# exit: 1
module Logstat.Main
expose Options, UsageError, Failure, options, analyzed, usage_line

use Logstat.Report{text, json}
use Logstat.Stats{Tally, empty_tally, add_lines, summarize}

intent "Summarize every .log file directly inside one folder, read one file at a time through an Fs scoped to that folder and read-only."

struct Options
  dir: String
  top: UInt64
  since: Option(Time)
  as_json: Bool
end

# The options so far, and the flag still waiting for its value, or "".
struct Parsing
  options: Options
  pending: String
end

enum UsageError
  NoFolder
  ExtraArgument(text: String)
  UnknownFlag(text: String)
  MissingValue(flag: String)
  BadTop(text: String)
  BadSince(text: String)
end

enum Failure
  Usage(problem: UsageError)
  NoLogs(dir: String)
  Unreadable(name: String)
end

fn options(args: List(String)) : Result(Options, UsageError)
  var parsing = Parsing(options: Options(dir: "", top: 5, since: None, as_json: false), pending: "")
  for arg in args
    parsing = try step(parsing, arg)
  end
  return Error(MissingValue(flag: parsing.pending)) if parsing.pending != ""
  return Error(NoFolder) if parsing.options.dir == ""
  Ok(parsing.options)
end

fn step(p: Parsing, arg: String) : Result(Parsing, UsageError)
  return value_for(p, arg) if p.pending != ""
  return Ok(Parsing(options: p.options, pending: arg)) if arg == "--top" or arg == "--since"
  return Ok(json_on(p)) if arg == "--json"
  return Error(UnknownFlag(text: arg)) if arg.starts_with?("-")
  return Error(ExtraArgument(text: arg)) if p.options.dir != ""
  var o = p.options
  o.dir = arg
  Ok(Parsing(options: o, pending: ""))
end

fn json_on(p: Parsing) : Parsing
  var o = p.options
  o.as_json = true
  Parsing(options: o, pending: "")
end

fn value_for(p: Parsing, value: String) : Result(Parsing, UsageError)
  var o = p.options
  if p.pending == "--top"
    o.top = try top_value(value)
  else
    at = try since_value(value)
    o.since = Some(at)
  end
  Ok(Parsing(options: o, pending: ""))
end

# Outside 1 to 100 is a usage error, never a clamp.
fn top_value(text: String) : Result(UInt64, UsageError)
  n = text.to_u64 or 0
  return Error(BadTop(text: text)) if n < 1 or n > 100
  Ok(n)
end

fn since_value(text: String) : Result(Time, UsageError)
  case Time.parse(text)
    Some(t): Ok(t)
    None: Error(BadSince(text: text))
  end
end

fn usage_line(e: UsageError) : String
  "logstat: #{reason(e)}; usage: logstat <dir> [--top N] [--since <ISO-8601>] [--json]"
end

fn reason(e: UsageError) : String
  case e
    NoFolder: "no folder given"
    ExtraArgument(text): "one folder only, and #{text} is a second"
    UnknownFlag(text): "#{text} is not a flag"
    MissingValue(flag): "#{flag} needs a value"
    BadTop(text): "--top takes a whole number from 1 to 100, not #{text}"
    BadSince(text): "--since takes a time such as 2026-09-12T10:00:00Z, not #{text}"
  end
end

# Every read goes through logs, which is scoped to the one folder, so no file outside it is read.
fn analyzed(fs: Fs, args: List(String)) : Result(String, Failure)
  case options(args)
    Ok(o): summary_text(fs.scoped(o.dir).read_only, o)
    Error(e): Error(Usage(problem: e))
  end
end

fn summary_text(logs: Fs, o: Options) : Result(String, Failure)
  names = try log_names(logs, o.dir)
  tally = try tally_files(logs, names, o.since)
  summary = summarize(tally, o.top)
  return Ok(json(summary)) if o.as_json
  Ok(text(summary))
end

# The *.log names directly inside the folder, in name order, as Fs.list gives them.
fn log_names(logs: Fs, dir: String) : Result(List(String), Failure)
  case logs.list(within: 1.minute)
    Ok(names): found(names.filter(fn(name) name.ends_with?(".log") end), dir)
    Error(_): Error(NoLogs(dir: dir))
  end
end

fn found(names: List(String), dir: String) : Result(List(String), Failure)
  return Error(NoLogs(dir: dir)) if names.size == 0
  Ok(names)
end

# One file's lines are in memory at a time: each is folded into the tally before the next is read.
fn tally_files(logs: Fs, names: List(String), since: Option(Time)) : Result(Tally, Failure)
  var tally = empty_tally()
  for name in names
    lines = try lines_of(logs, name)
    tally = add_lines(tally, lines, since)
  end
  Ok(tally)
end

fn lines_of(logs: Fs, name: String) : Result(List(String), Failure)
  case logs.read_lines(name, within: 1.minute)
    Ok(lines): Ok(lines)
    Error(_): Error(Unreadable(name: name))
  end
end

fn main(platform: Platform)
  case analyzed(platform.fs.read_only, platform.args)
    Ok(report): platform.stdout.write(report)
    Error(Usage(problem)):
      platform.stderr.write_line(usage_line(problem))
      platform.exit(2)
    Error(NoLogs(dir)):
      platform.stderr.write_line("logstat: no .log file directly inside #{dir}")
      platform.exit(1)
    Error(Unreadable(name)):
      platform.stderr.write_line("logstat: #{name} could not be read within a minute")
      platform.exit(1)
  end
end

test "a folder alone takes every default"
  assert options(["logs"]) is Ok(o)
  assert o == Options(dir: "logs", top: 5, since: None, as_json: false)
end

test "flags go before or after the folder"
  args = ["--json", "--top", "3", "logs", "--since", "2026-09-12T10:00:00Z"]
  assert options(args) is Ok(o)
  assert o.dir == "logs" and o.top == 3 and o.as_json
  assert o.since == Time.parse("2026-09-12T10:00:00Z")
end

test "a top outside 1 to 100 is a usage error, not a clamp"
  assert options(["logs", "--top", "1"]) is Ok(_)
  assert options(["logs", "--top", "100"]) is Ok(_)
  assert options(["logs", "--top", "0"]) is Error(BadTop("0"))
  assert options(["logs", "--top", "101"]) is Error(BadTop("101"))
  assert options(["logs", "--top", "ten"]) is Error(BadTop("ten"))
end

test "every other usage error"
  assert options([]) is Error(NoFolder)
  assert options(["a", "b"]) is Error(ExtraArgument("b"))
  assert options(["logs", "--verbose"]) is Error(UnknownFlag("--verbose"))
  assert options(["logs", "--top"]) is Error(MissingValue("--top"))
  assert options(["logs", "--since", "noon"]) is Error(BadSince("noon"))
  assert !usage_line(BadTop(text: "0")).contains?("\n")
end

test "a usage error is found before any file is touched"
  assert analyzed(Fs.fixture(), ["--top", "0", "logs"]) is Error(Usage(BadTop("0")))
end

test "a folder with no log file, or one that cannot be listed, is no logs"
  assert analyzed(Fs.fixture(), ["logs"]) is Error(NoLogs("logs"))
  assert analyzed(Fs.fixture(delay: 2.minute), ["logs"]) is Error(NoLogs("logs"))
end
