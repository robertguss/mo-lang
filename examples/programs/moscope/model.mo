module Model
expose Mode, Options, BlockKind, Block, Message, Seen, Issue, Scan, Discovery, Hit, Session, Report, empty_scan, empty_discovery

intent "The bounded values shared by moscope's argument parser, serial scanner, search, and renderer."

enum Mode
  Phrase
  AllWords
end

struct Options
  query: String
  dir: String
  mode: Mode
  include_tools: Bool
end

enum BlockKind
  Conversation
  Tool
end

struct Block
  kind: BlockKind
  label: String
  text: String
  path: String
  line: UInt64
  local_index: UInt64
  api_index: Option(UInt64)
end

# One logical message. Its key is file-local even when its session heading is shared with
# another file. Blocks keep their own physical line and content-array provenance.
struct Message
  key: String
  session_key: String
  session_label: String
  role: String
  id: String
  path: String
  first_line: UInt64
  conversation_at: Option(Time)
  blocks: List(Block)
end

# A UUID is deduplicated only inside one file. Equality is structural equality of the complete
# decoded JSON record, not equality of selected message fields.
struct Seen
  payload: Json
  line: UInt64
end

struct Issue
  path: String
  line: UInt64
  detail: String
end

struct Scan
  messages: Map(String, Message)
  issues: List(Issue)
  unknown_kinds: Map(String, UInt64)
  skipped_links: UInt64
  files_read: UInt64
  admitted_bytes: UInt64
  records: UInt64
  retained_blocks: UInt64
  incomplete: Bool
end

struct Discovery
  files: List(String)
  issues: List(Issue)
  entries: UInt64
  skipped_links: UInt64
  incomplete: Bool
  stopped: Bool
end

struct Hit
  entry: Message
  blocks: List(Block)
end

struct Session
  key: String
  label: String
  latest: Option(Time)
  hits: List(Hit)
end

struct Report
  text: String
  diagnostics: String
  matches: UInt64
  incomplete: Bool
end

fn empty_scan() : Scan
  Scan(messages: Map.new(), issues: [], unknown_kinds: Map.new(), skipped_links: 0, files_read: 0,
    admitted_bytes: 0, records: 0, retained_blocks: 0, incomplete: false)
end

fn empty_discovery() : Discovery
  Discovery(files: [], issues: [], entries: 0, skipped_links: 0, incomplete: false, stopped: false)
end

test "empty production state starts every counter and stop flag clear"
  scan = empty_scan()
  assert scan.messages.size == 0 and scan.issues.size == 0 and scan.unknown_kinds.size == 0
  assert scan.skipped_links == 0 and scan.files_read == 0 and scan.admitted_bytes == 0
  assert scan.records == 0 and scan.retained_blocks == 0 and !scan.incomplete
  found = empty_discovery()
  assert found.files.size == 0 and found.issues.size == 0 and found.entries == 0
  assert found.skipped_links == 0 and !found.incomplete and !found.stopped
end

verified: types, contracts, tests (1), property (0 seeds), sim (not run)
          proven: not run
