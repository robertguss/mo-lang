module Model
expose Mode, Options, Matcher, BlockKind, Block, Message, SessionInfo, Issue, Warning, Scan, Discovery, Session, Report, empty_scan, empty_discovery, failed, warned, later

use Limits{diagnostics, warning_kinds}

intent "The bounded values shared by moscope's argument parser, streaming scanner, matcher, and renderer."

enum Mode
  Phrase
  AllWords
end

struct Options
  query: String
  dir: String
  mode: Mode
  include_tools: Bool
  strict: Bool
end

# The query, lowered once. A phrase matcher has one term, the whole lowered query.
struct Matcher
  mode: Mode
  terms: List(String)
  include_tools: Bool
end

enum BlockKind
  Conversation
  Tool
end

# One matching block. Only its terminal-safe excerpt is kept, never the whole text.
struct Block
  kind: BlockKind
  label: String
  excerpt: String
  path: String
  line: UInt64
  local_index: UInt64
  api_index: Option(UInt64)
end

# One logical message with at least one matching block. Its key is file-local even when its
# session heading is shared with another file. `found` holds one flag per matcher term.
struct Message
  key: String
  session_key: String
  role: String
  id: String
  path: String
  first_line: UInt64
  found: List(Bool)
  blocks: List(Block)
end

# What a heading needs, kept for every session seen whether or not it matches. A session without
# an id is file-local and is named by `path`.
struct SessionInfo
  key: String
  path: String
  id: String
  cwd: String
  latest: Option(Time)
end

struct Issue
  path: String
  line: UInt64
  detail: String
end

# A skipped record or block, counted by category with its first location.
struct Warning
  count: UInt64
  path: String
  line: UInt64
end

struct Scan
  candidates: Map(String, Message)
  sessions: Map(String, SessionInfo)
  errors: List(Issue)
  warnings: Map(String, Warning)
  ignored: Map(String, UInt64)
  skipped_links: UInt64
  files_read: UInt64
  records: UInt64
  retained_blocks: UInt64
end

struct Discovery
  files: List(String)
  errors: List(Issue)
  entries: UInt64
  skipped_links: UInt64
  stopped: Bool
end

struct Session
  info: SessionInfo
  hits: List(Message)
end

struct Report
  text: String
  diagnostics: String
  matches: UInt64
  incomplete: Bool
end

fn empty_scan() : Scan
  Scan(candidates: Map.new(), sessions: Map.new(), errors: [], warnings: Map.new(),
    ignored: Map.new(), skipped_links: 0, files_read: 0, records: 0, retained_blocks: 0)
end

fn empty_discovery() : Discovery
  Discovery(files: [], errors: [], entries: 0, skipped_links: 0, stopped: false)
end

# An error makes the search incomplete. The list is bounded; the renderer says when it filled.
fn failed(errors: List(Issue), path: String, line: UInt64, detail: String) : List(Issue)
  return errors if errors.size >= diagnostics()
  errors.push(Issue(path: path, line: line, detail: detail))
end

# A warning counts one skipped record or block under its category.
fn warned(scan: Scan, path: String, line: UInt64, category: String) : Scan
  var next = scan
  known = next.warnings.has?(category)
  key = if known or next.warnings.size < warning_kinds(): category else: "other warnings"
  # update applies the function to the default when the key is new.
  first = Warning(count: 0, path: path, line: line)
  next.warnings = next.warnings.update(key, first, fn(before)
    Warning(count: before.count.saturating_add(1), path: before.path, line: before.line)
  end)
  next
end

fn later(a: Option(Time), b: Option(Time)) : Option(Time)
  case (a, b)
    (Some(left), Some(right)): Some(max_of(left, right))
    (Some(left), None): Some(left)
    (None, Some(right)): Some(right)
    (None, None): None
  end
end

test "empty production state starts every counter clear"
  scan = empty_scan()
  assert scan.candidates.size == 0 and scan.sessions.size == 0 and scan.errors.size == 0
  assert scan.warnings.size == 0 and scan.ignored.size == 0 and scan.skipped_links == 0
  assert scan.files_read == 0 and scan.records == 0 and scan.retained_blocks == 0
  found = empty_discovery()
  assert found.files.size == 0 and found.errors.size == 0 and found.entries == 0
  assert found.skipped_links == 0 and !found.stopped
end

test "warnings count by category and keep their first location"
  once = warned(empty_scan(), "a.jsonl", 3, "malformed JSON record")
  twice = warned(once, "b.jsonl", 9, "malformed JSON record")
  assert twice.warnings.get("malformed JSON record") == Some(Warning(count: 2, path: "a.jsonl",
    line: 3))
end

test "errors are retained up to the diagnostic limit"
  one = failed([], "a", 0, "x")
  assert one.size == 1 and one.first == Some(Issue(path: "a", line: 0, detail: "x"))
end

verified: types, contracts, tests (3), property (0 seeds), sim (not run)
          proven: not run
