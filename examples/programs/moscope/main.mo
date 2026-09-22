# run: search Please fixtures/smoke
# run: search definitely-absent fixtures/smoke
# exit: 1
# run: search needle fixtures/warnings/nonobject --strict
# exit: 2
module Main
expose Problem, options, analyze, main

use Find{matcher_of, query_terms}
use Limits{query_bytes, terms}
use Model{Mode, Options, Report}
use Scan{scan_tree}
use Search{report}
use Term{safe_prefix}

intent "Search Claude Code JSONL histories under one operator-supplied directory with a streaming serial read-only scan; matches exit 0, no matches exit 1, and usage errors or an incomplete scan exit 2."

enum Problem
  Usage(detail: String)
  Help
end

# Arguments after `search`, gathered one at a time.
struct Arguments
  positionals: List(String)
  all_words: Bool
  include_tools: Bool
  strict: Bool
  ended: Bool
end

fn usage() : String
  "usage: moscope search [--all-words] [--include-tools] [--strict] [--] <query> <directory>"
end

fn help() : String
  lines = [usage(),
    "",
    "Search Claude Code session histories (JSONL) under <directory>, for example ~/.claude/projects.",
    "Matching is a literal substring, ASCII-case-insensitive, inside one text block.",
    "",
    "  --all-words      match messages holding every whitespace-separated term, in any of their blocks",
    "  --include-tools  also search tool calls and tool results",
    "  --strict         treat skipped or unrecognized records as errors (exit 2)",
    "  --               end options; use it before a query that starts with -",
    "  -h, --help       show this help",
    "",
    "Exit status: 0 matches found, 1 no matches, 2 usage error or incomplete search."]
  "#{String.join(lines, "\n")}\n"
end

fn options(args: List(String)) : Result(Options, Problem)
  first = args.first or ""
  return Error(Help) if first == "-h" or first == "--help" or first == "help"
  return Error(Usage(detail: "the first argument must be search")) if first != "search"
  var gathered = Arguments(positionals: [], all_words: false, include_tools: false, strict: false,
    ended: false)
  for arg in args.drop(1)
    case argument(gathered, arg)
      Ok(next):
        gathered = next
      Error(problem):
        return Error(problem)
    end
  end
  checked(gathered)
end

fn argument(so_far: Arguments, arg: String) : Result(Arguments, Problem)
  var next = so_far
  if next.ended or !arg.starts_with?("-") or arg == "-"
    next.positionals = next.positionals.push(arg)
    return Ok(next)
  end
  case arg
    "--":
      next.ended = true
    "-h" | "--help":
      return Error(Help)
    "--all-words":
      return Error(Usage(detail: "duplicate --all-words")) if next.all_words
      next.all_words = true
    "--include-tools":
      return Error(Usage(detail: "duplicate --include-tools")) if next.include_tools
      next.include_tools = true
    "--strict":
      return Error(Usage(detail: "duplicate --strict")) if next.strict
      next.strict = true
    _:
      return Error(Usage(detail: "unsupported option #{safe_prefix(arg, 256)}"))
  end
  Ok(next)
end

fn checked(gathered: Arguments) : Result(Options, Problem)
  if gathered.positionals.size != 2
    return Error(Usage(detail: "search needs exactly one query and one directory"))
  end
  query = gathered.positionals.get(0) or ""
  dir = gathered.positionals.get(1) or ""
  return Error(Usage(detail: "query exceeds #{query_bytes()} bytes")) if query.byte_size > query_bytes()
  words = query_terms(query)
  return Error(Usage(detail: "query is empty or ASCII whitespace only")) if words.size == 0
  if gathered.all_words and words.size > terms()
    return Error(Usage(detail: "--all-words query exceeds #{terms()} terms"))
  end
  return Error(Usage(detail: "directory is empty")) if dir == ""
  mode = if gathered.all_words: AllWords else: Phrase
  Ok(Options(query: query, dir: dir, mode: mode, include_tools: gathered.include_tools,
    strict: gathered.strict))
end

fn analyze(fs: Fs, parsed: Options) : Report
  root = fs.scoped(parsed.dir).read_only
  report(scan_tree(root, matcher_of(parsed)), parsed)
end

fn main(platform: Platform)
  case options(platform.args)
    Error(Help): platform.stdout.write(help())
    Error(Usage(detail)):
      platform.stderr.write_line("moscope: #{detail}\n#{usage()}")
      platform.exit(2)
    Ok(parsed):
      result = analyze(platform.fs, parsed)
      platform.stdout.write(result.text)
      if result.diagnostics != ""
        platform.stderr.write(result.diagnostics)
      end
      if result.incomplete
        platform.exit(2)
      else
        if result.matches == 0
          platform.exit(1)
        end
      end
  end
end

test "flags combine in either order and duplicate or unsupported arguments are rejected"
  assert options(["search", "needle", "sessions", "--all-words", "--include-tools"]) is Ok(both)
  assert both.mode == AllWords and both.include_tools and !both.strict
  assert options(["search", "--strict", "needle", "--include-tools", "sessions"]) is Ok(strict)
  assert strict.strict and strict.mode == Phrase
  assert options(["search", "needle", "sessions", "--all-words", "--all-words"]) is Error(Usage(_))
  assert options(["search", "needle", "sessions", "--strict", "--strict"]) is Error(Usage(_))
  assert options(["search", "needle", "sessions", "--regex"]) is Error(Usage(_))
  assert options(["find", "needle", "sessions"]) is Error(Usage(_))
  assert options([]) is Error(Usage(_))
end

test "-- ends options so a query may start with a dash"
  assert options(["search", "--", "--no-verify", "sessions"]) is Ok(dashed)
  assert dashed.query == "--no-verify" and dashed.dir == "sessions"
  assert options(["search", "--all-words", "--", "-rf", "--force", "sessions"]) is Error(Usage(_))
  assert options(["search", "-", "sessions"]) is Ok(_)
end

test "help is asked for, not an error"
  assert options(["--help"]) is Error(Help)
  assert options(["-h"]) is Error(Help)
  assert options(["search", "needle", "--help"]) is Error(Help)
  assert options(["search", "--", "--help", "sessions"]) is Ok(_)
end

test "blank, oversized, and wrongly counted arguments are usage errors at exact boundaries"
  assert options(["search", " \t\n\u{000B}\u{000C}\r", "sessions"]) is Error(Usage(_))
  assert options(["search", "x".repeat(4_096), "sessions"]) is Ok(_)
  assert options(["search", "x".repeat(4_097), "sessions"]) is Error(Usage(_))
  assert options(["search", "x ".repeat(64), "sessions", "--all-words"]) is Ok(_)
  assert options(["search", "x ".repeat(65), "sessions", "--all-words"]) is Error(Usage(_))
  assert options(["search", "x ".repeat(65), "sessions"]) is Ok(_)
  assert options(["search", "needle"]) is Error(Usage(_))
  assert options(["search", "needle", ""]) is Error(Usage(_))
end

verified: types, contracts, tests (4), property (0 seeds), sim (not run)
          proven: not run
