# run: search connection fixtures/smoke
# run: search refused fixtures/smoke --all-words --include-tools
module Moscope.Main
expose Problem, options, analyze, main

use Moscope.Limits{query_bytes, terms}
use Moscope.Model{Mode, Options, Report}
use Moscope.Scan{scan_tree}
use Moscope.Search{report, query_terms, safe}

intent "Search Claude Code JSONL histories under one operator-supplied directory with a bounded serial read-only scan; complete matches exit 0, complete absence exits 1, and usage or incomplete results exit 2."

enum Problem
  Usage(detail: String)
end

fn usage() : String
  "usage: moscope search <query> <directory> [--all-words] [--include-tools]"
end

fn options(args: List(String)) : Result(Options, Problem)
  if args.first != Some("search")
    return Error(Usage(detail: "the first argument must be search"))
  end
  var positionals: List(String) = []
  var all_words = false
  var include_tools = false
  for arg in args.drop(1)
    if arg == "--all-words"
      return Error(Usage(detail: "duplicate --all-words")) if all_words
      all_words = true
    else
      if arg == "--include-tools"
        return Error(Usage(detail: "duplicate --include-tools")) if include_tools
        include_tools = true
      else
        return Error(Usage(detail: "unsupported option #{safe(arg)}")) if arg.starts_with?("-")
        positionals = positionals.push(arg)
      end
    end
  end
  if positionals.size != 2
    return Error(Usage(detail: "search needs exactly one query and one directory"))
  end
  query = positionals.get(0) or ""
  dir = positionals.get(1) or ""
  return Error(Usage(detail: "query is empty or ASCII whitespace only")) if query_terms(query).size == 0
  return Error(Usage(detail: "query exceeds 4096 bytes")) if query.byte_size > query_bytes()
  if all_words and query_terms(query).size > terms()
    return Error(Usage(detail: "--all-words query exceeds 64 terms"))
  end
  return Error(Usage(detail: "directory is empty")) if dir == ""
  mode = if all_words: AllWords else: Phrase
  Ok(Options(query: query, dir: dir, mode: mode, include_tools: include_tools))
end

fn analyze(fs: Fs, clock: Clock, parsed: Options) : Report
  started = clock.now
  root = fs.scoped(parsed.dir).read_only
  report(scan_tree(root, clock, started), parsed, clock, started)
end

fn main(platform: Platform)
  case options(platform.args)
    Error(Usage(detail)):
      platform.stderr.write_line("moscope: #{detail}; #{usage()}")
      platform.exit(2)
    Ok(parsed):
      result = analyze(platform.fs, platform.clock, parsed)
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
  assert both.mode == AllWords and both.include_tools
  assert options(["search", "needle", "sessions", "--include-tools", "--all-words"]) is Ok(_)
  assert options(["search", "needle", "sessions", "--all-words", "--all-words"]) is Error(Usage(_))
  assert options(["search", "needle", "sessions", "--regex"]) is Error(Usage(_))
  assert options(["find", "needle", "sessions"]) is Error(Usage(_))
end

test "blank and oversized queries and malformed positional counts are usage errors"
  assert options(["search", " \t\r\n", "sessions"]) is Error(Usage(_))
  assert options(["search", "x".repeat(4_097), "sessions"]) is Error(Usage(_))
  assert options(["search", "needle"]) is Error(Usage(_))
  assert options(["search", "needle", "one", "two"]) is Error(Usage(_))
end
