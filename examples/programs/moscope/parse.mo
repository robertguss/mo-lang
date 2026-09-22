module Parse
expose FileFold, start_file, folded_line

use Find{Found, found_in, eligible?}
use Limits{line_bytes, candidates, blocks, warning_kinds}
use Model{Mode, Matcher, BlockKind, Block, Message, SessionInfo, Scan, empty_scan, failed, warned, later}

intent "Decode JSONL records one at a time, match each eligible block as it is read, and keep only matching blocks with their provenance; skip what cannot be read with a counted warning."

struct FileFold
  scan: Scan
  matcher: Matcher
  seen: Map(String, UInt64)
  path: String
  lines: UInt64
end

# Where a conversation record sits and what it says about its session.
struct Record
  path: String
  line: UInt64
  role: String
  session: String
  cwd: String
  at: Option(Time)
end

# A searchable block before matching.
struct Raw
  kind: BlockKind
  label: String
  text: String
  local: UInt64
  api: Option(UInt64)
end

struct Parsed
  scan: Scan
  raws: List(Raw)
end

struct Hits
  blocks: List(Block)
  flags: List(Bool)
end

struct Identity
  kind: String
  value: String
  label: String
end

fn start_file(scan: Scan, matcher: Matcher, path: String) : FileFold
  FileFold(scan: scan, matcher: matcher, seen: Map.new(), path: path, lines: 0)
end

fn folded_line(state: FileFold, line: String) : FileFold
  var next = state
  next.lines += 1
  return next if line.byte_size == 0
  if line.byte_size > line_bytes()
    next.scan = warned(next.scan, next.path, next.lines, "a line over 32 MiB was skipped")
    return next
  end
  next.scan.records += 1
  # fold_lines turns malformed UTF-8 into U+FFFD, indistinguishable from a genuine one.
  if line.contains?("\u{FFFD}")
    next.scan = warned(next.scan, next.path, next.lines,
      "a record holding U+FFFD (possibly replaced invalid UTF-8) was searched as read")
  end
  case Json.decode(line)
    Ok(payload): record(next, payload)
    Error(_):
      next.scan = warned(next.scan, next.path, next.lines, "a malformed JSON record was skipped")
      next
  end
end

fn record(state: FileFold, payload: Json) : FileFold
  var next = state
  fields = case payload
    Object(given): given
    String(_) | Array(_) | Number(_) | Bool(_) | Null:
      next.scan = warned(next.scan, next.path, next.lines, "a non-object record was skipped")
      return next
  end
  kind = case fields.get("type")
    Some(String(name)): name
    None | Some(Object(_)) | Some(Array(_)) | Some(Number(_)) | Some(Bool(_)) | Some(Null):
      next.scan = warned(next.scan, next.path, next.lines,
        "a record without a string type was skipped")
      return next
  end
  if kind != "user" and kind != "assistant"
    next.scan = bookkeeping(next.scan, next.path, next.lines, kind, fields)
    return next
  end
  if marked?(fields, "isMeta") or marked?(fields, "isCompactSummary") or marked?(fields,
    "isApiErrorMessage")
    return next
  end
  unique = first_uuid(next, fields)
  next = unique.0
  if unique.1
    next.scan = conversation(next.scan, next.matcher, next.path, next.lines, kind, fields)
  end
  next
end

# The bool says whether to process the record: a repeated UUID in one file keeps the first.
fn first_uuid(state: FileFold, fields: Map(String, Json)) : (FileFold, Bool)
  var next = state
  case fields.get("uuid")
    None: (next, true)
    Some(String(uuid)):
      if next.seen.has?(uuid)
        next.scan = warned(next.scan, next.path, next.lines,
          "a record repeating an earlier UUID in its file was skipped")
        return (next, false)
      end
      next.seen = next.seen.set(uuid, next.lines)
      (next, true)
    Some(Object(_)) | Some(Array(_)) | Some(Number(_)) | Some(Bool(_)) | Some(Null):
      next.scan = warned(next.scan, next.path, next.lines, "a conversation uuid is not a string")
      (next, true)
  end
end

fn bookkeeping(scan: Scan, path: String, line: UInt64, kind: String,
  fields: Map(String, Json)) : Scan
  var next = scan
  clipped = if kind.size <= 128: kind else: "#{kind.slice(0, 128)}..."
  if fields.get("message") is Some(Object(_))
    return warned(next, path, line,
      "a record of unknown type #{clipped} with a conversation-shaped message was skipped")
  end
  known = next.ignored.has?(clipped)
  key = if known or next.ignored.size < warning_kinds(): clipped else: "other kinds"
  next.ignored = next.ignored.update(key, 0, fn(n) n.saturating_add(1) end)
  next
end

fn conversation(scan: Scan, matcher: Matcher, path: String, line: UInt64, kind: String,
  fields: Map(String, Json)) : Scan
  session = text_field(scan, path, line, fields, "sessionId")
  cwd = text_field(session.0, path, line, fields, "cwd")
  timed = timestamp_of(cwd.0, path, line, fields)
  place = Record(path: path, line: line, role: kind, session: session.1, cwd: cwd.1, at: timed.1)
  message_record(timed.0, matcher, place, fields)
end

fn text_field(scan: Scan, path: String, line: UInt64, fields: Map(String, Json),
  name: String) : (Scan, String)
  case fields.get(name)
    Some(String(value)): (scan, value)
    None: (scan, "")
    Some(Object(_)) | Some(Array(_)) | Some(Number(_)) | Some(Bool(_)) | Some(Null):
      (warned(scan, path, line, "a conversation #{name} is not a string"), "")
  end
end

fn timestamp_of(scan: Scan, path: String, line: UInt64, fields: Map(String, Json)) : (Scan,
  Option(Time))
  case fields.get("timestamp")
    Some(String(text)):
      case Time.parse(text)
        Some(parsed): (scan, Some(parsed))
        None: (warned(scan, path, line, "a conversation timestamp is not RFC 3339"), None)
      end
    None: (scan, None)
    Some(Object(_)) | Some(Array(_)) | Some(Number(_)) | Some(Bool(_)) | Some(Null):
      (warned(scan, path, line, "a conversation timestamp is not a string"), None)
  end
end

fn message_record(scan: Scan, matcher: Matcher, place: Record, fields: Map(String, Json)) : Scan
  message_fields = case fields.get("message")
    Some(Object(given)): given
    None | Some(String(_)) | Some(Array(_)) | Some(Number(_)) | Some(Bool(_)) | Some(Null):
      return warned(scan, place.path, place.line,
        "a conversation without a message object was skipped")
  end
  role = case message_fields.get("role")
    Some(String(name)): name
    None | Some(Object(_)) | Some(Array(_)) | Some(Number(_)) | Some(Bool(_)) | Some(Null):
      return warned(scan, place.path, place.line,
        "a conversation without a string role was skipped")
  end
  if role != place.role
    return warned(scan, place.path, place.line,
      "a conversation whose type and message role disagree was skipped")
  end
  identified = identity_of(scan, place, message_fields)
  parsed = case message_fields.get("content")
    Some(String(text)): Parsed(scan: identified.0, raws: [conversation_raw(role, text, 0, None)])
    Some(Array(items)): raws_of(identified.0, place, items)
    None | Some(Object(_)) | Some(Number(_)) | Some(Bool(_)) | Some(Null):
      return warned(identified.0, place.path, place.line,
        "a conversation whose content is neither text nor a block array was skipped")
  end
  retain(parsed.scan, matcher, place, identified.1, parsed.raws)
end

fn identity_of(scan: Scan, place: Record, fields: Map(String, Json)) : (Scan, Identity)
  physical = Identity(kind: "physical", value: "#{place.line}", label: "physical:#{place.line}")
  case fields.get("id")
    Some(String(value)): (scan, Identity(kind: "provided", value: value, label: value))
    None: (scan, physical)
    Some(Object(_)) | Some(Array(_)) | Some(Number(_)) | Some(Bool(_)) | Some(Null):
      (warned(scan, place.path, place.line, "a message id is not a string"), physical)
  end
end

# Session headings need every session's latest eligible conversation time, matching or not.
fn retain(scan: Scan, matcher: Matcher, place: Record, identity: Identity, raws: List(Raw)) : Scan
  var next = touched(scan, place, raws)
  hits = hits_of(matcher, place, raws)
  return next if hits.blocks.size == 0
  key = Json.encode((place.path, session_key(place), place.role, identity.kind, identity.value))
  existing = next.candidates.get(key)
  if existing is None and next.candidates.size >= candidates()
    next.errors = failed(next.errors, place.path, place.line,
      "more than #{candidates()} candidate messages would be retained")
    return next
  end
  if next.retained_blocks.saturating_add(hits.blocks.size) > blocks()
    next.errors = failed(next.errors, place.path, place.line,
      "more than #{blocks()} matching blocks would be retained")
    return next
  end
  next.retained_blocks += hits.blocks.size
  made = Message(key: key, session_key: session_key(place), role: place.role, id: identity.label,
    path: place.path, first_line: place.line, found: hits.flags, blocks: hits.blocks)
  merged = case existing
    Some(before): merged_message(before, hits)
    None: made
  end
  next.candidates = next.candidates.set(key, merged)
  next
end

fn merged_message(before: Message, hits: Hits) : Message
  var after = before
  after.found = either(before.found, hits.flags)
  after.blocks = before.blocks.concat(hits.blocks)
  after
end

fn hits_of(matcher: Matcher, place: Record, raws: List(Raw)) : Hits
  var hits = Hits(blocks: [], flags: [])
  for raw in raws.filter(fn(one) eligible?(matcher, one.kind) end)
    if found_in(matcher, raw.kind, raw.label, raw.text) is Some(found)
      hits.blocks = hits.blocks.push(block_of_hit(place, raw, found))
      hits.flags = either(hits.flags, found.flags)
    end
  end
  hits
end

# Term flags joined by or; an empty list means no term seen yet.
fn either(a: List(Bool), b: List(Bool)) : List(Bool)
  return b if a.size == 0
  a.enumerate.map(fn(pair) pair.1 or (b.get(pair.0) or false) end)
end

fn block_of_hit(place: Record, raw: Raw, found: Found) : Block
  Block(kind: raw.kind, label: raw.label, excerpt: found.excerpt, path: place.path,
    line: place.line, local_index: raw.local, api_index: raw.api)
end

fn session_key(place: Record) : String
  if place.session == "": "file:#{place.path}" else: "session:#{place.session}"
end

fn touched(scan: Scan, place: Record, raws: List(Raw)) : Scan
  var next = scan
  key = session_key(place)
  fresh = SessionInfo(key: key, path: place.path, id: place.session, cwd: place.cwd, latest: None)
  var info = next.sessions.get(key) or fresh
  if info.cwd == ""
    info.cwd = place.cwd
  end
  if raws.any?(fn(raw) raw.kind == Conversation end)
    info.latest = later(info.latest, place.at)
  end
  next.sessions = next.sessions.set(key, info)
  next
end

fn raws_of(scan: Scan, place: Record, items: List(Json)) : Parsed
  var parsed = Parsed(scan: scan, raws: [])
  for pair in items.enumerate
    one = raw_of(parsed.scan, place, pair.0, pair.1)
    parsed.scan = one.scan
    parsed.raws = parsed.raws.concat(one.raws)
  end
  parsed
end

fn raw_of(scan: Scan, place: Record, local: UInt64, value: Json) : Parsed
  fields = case value
    Object(given): given
    String(_) | Array(_) | Number(_) | Bool(_) | Null:
      return skipped(scan, place, "a non-object content block was skipped")
  end
  kind = case fields.get("type")
    Some(String(name)): name
    None | Some(Object(_)) | Some(Array(_)) | Some(Number(_)) | Some(Bool(_)) | Some(Null):
      return skipped(scan, place, "a content block without a string type was skipped")
  end
  api = api_index(scan, place, fields)
  case kind
    "text":
      case fields.get("text")
        Some(String(text)):
          Parsed(scan: api.0, raws: [conversation_raw(place.role, text, local, api.1)])
        None | Some(Object(_)) | Some(Array(_)) | Some(Number(_)) | Some(Bool(_)) | Some(Null):
          skipped(api.0, place, "a text block without string text was skipped")
      end
    "thinking" | "redacted_thinking" | "image" | "document": Parsed(scan: api.0, raws: [])
    "tool_use": tool_use(api.0, place, local, api.1, fields)
    "tool_result": tool_result(api.0, place, local, api.1, fields)
    _: skipped(api.0, place, "a content block of unsupported type #{clip(kind)} was skipped")
  end
end

fn skipped(scan: Scan, place: Record, category: String) : Parsed
  Parsed(scan: warned(scan, place.path, place.line, category), raws: [])
end

fn clip(text: String) : String
  if text.size <= 64: text else: "#{text.slice(0, 64)}..."
end

fn conversation_raw(role: String, text: String, local: UInt64, api: Option(UInt64)) : Raw
  Raw(kind: Conversation, label: "#{role} text", text: text, local: local, api: api)
end

fn tool_use(scan: Scan, place: Record, local: UInt64, api: Option(UInt64),
  fields: Map(String, Json)) : Parsed
  name = case fields.get("name")
    Some(String(value)): value
    None | Some(Object(_)) | Some(Array(_)) | Some(Number(_)) | Some(Bool(_)) | Some(Null):
      return skipped(scan, place, "a tool_use block without a string name was skipped")
  end
  input = case fields.get("input")
    Some(value): value
    None:
      return skipped(scan, place, "a tool_use block without input was skipped")
  end
  raw = Raw(kind: Tool, label: "tool #{name} arguments", text: Json.encode(input), local: local,
    api: api)
  Parsed(scan: scan, raws: [raw])
end

fn tool_result(scan: Scan, place: Record, local: UInt64, api: Option(UInt64),
  fields: Map(String, Json)) : Parsed
  id = case fields.get("tool_use_id")
    Some(String(value)): value
    None: "unknown"
    Some(Object(_)) | Some(Array(_)) | Some(Number(_)) | Some(Bool(_)) | Some(Null):
      return skipped(scan, place, "a tool_result block with a non-string tool_use_id was skipped")
  end
  base = Raw(kind: Tool, label: "tool result #{id}", text: "", local: local, api: api)
  case fields.get("content")
    Some(String(text)):
      var raw = base
      raw.text = text
      Parsed(scan: scan, raws: [raw])
    Some(Array(items)): result_parts(scan, place, base, items)
    None | Some(Object(_)) | Some(Number(_)) | Some(Bool(_)) | Some(Null):
      skipped(scan, place, "a tool_result block with unsupported content was skipped")
  end
end

fn result_parts(scan: Scan, place: Record, base: Raw, items: List(Json)) : Parsed
  var parsed = Parsed(scan: scan, raws: [])
  for pair in items.enumerate
    var labelled = base
    labelled.label = "#{base.label} part #{pair.0}"
    one = result_part(parsed.scan, place, labelled, pair.1)
    parsed.scan = one.scan
    parsed.raws = parsed.raws.concat(one.raws)
  end
  parsed
end

# Text parts are searchable; a tool_reference part is searchable by the tool's name.
fn result_part(scan: Scan, place: Record, base: Raw, value: Json) : Parsed
  fields = case value
    Object(given): given
    String(_) | Array(_) | Number(_) | Bool(_) | Null:
      return skipped(scan, place, "a non-object tool result part was skipped")
  end
  case fields.get("type")
    Some(String("text")): part_text(scan, place, base, fields, "text")
    Some(String("tool_reference")): part_text(scan, place, base, fields, "tool_name")
    Some(String("image")) | Some(String("document")): Parsed(scan: scan, raws: [])
    Some(String(kind)):
      skipped(scan, place, "a tool result part of unsupported type #{clip(kind)} was skipped")
    None | Some(Object(_)) | Some(Array(_)) | Some(Number(_)) | Some(Bool(_)) | Some(Null):
      skipped(scan, place, "a tool result part without a string type was skipped")
  end
end

fn part_text(scan: Scan, place: Record, base: Raw, fields: Map(String, Json), name: String) : Parsed
  case fields.get(name)
    Some(String(text)):
      var raw = base
      raw.text = text
      Parsed(scan: scan, raws: [raw])
    None | Some(Object(_)) | Some(Array(_)) | Some(Number(_)) | Some(Bool(_)) | Some(Null):
      skipped(scan, place, "a tool result part without string #{name} was skipped")
  end
end

# The explicit API block index. A local array index is never substituted for an absent one.
fn api_index(scan: Scan, place: Record, fields: Map(String, Json)) : (Scan, Option(UInt64))
  case fields.get("apiBlockIndex")
    None: (scan, None)
    Some(value):
      case value.to_i64
        Some(n):
          if n >= 0
            (scan, Some(n.to_u64))
          else
            (warned(scan, place.path, place.line, "a negative apiBlockIndex was ignored"), None)
          end
        None:
          (warned(scan, place.path, place.line, "a non-integer apiBlockIndex was ignored"), None)
      end
  end
end

fn marked?(fields: Map(String, Json), name: String) : Bool
  fields.get(name) == Some(Bool(value: true))
end

fn phrase(query: String) : Matcher
  Matcher(mode: Phrase, terms: [query.to_lower], include_tools: true)
end

fn folded(matcher: Matcher, lines: List(String)) : FileFold
  lines.reduce(start_file(empty_scan(), matcher, "one.jsonl"),
    fn(state, line) folded_line(state, line) end)
end

fn user(uuid: String, id: String, content: String) : String
  "{\"type\":\"user\",\"uuid\":\"#{uuid}\",\"sessionId\":\"s\",\"cwd\":\"/work\",\"timestamp\":\"2026-09-21T10:00:00Z\",\"message\":{\"role\":\"user\",\"id\":\"#{id}\",\"content\":#{content}}}"
end

test "only matching blocks are retained, while every session keeps its heading facts"
  done = folded(phrase("needle"), [user("a", "m1", "\"has needle\""), user("b", "m2", "\"plain\"")])
  assert done.scan.candidates.size == 1 and done.scan.retained_blocks == 1
  assert done.scan.records == 2 and done.scan.errors.size == 0 and done.scan.warnings.size == 0
  info = done.scan.sessions.get("session:s")
  assert info is Some(seen)
  assert seen.cwd == "/work" and seen.latest is Some(_)
end

test "unreadable records are counted warnings and neighbouring records survive"
  lines = [user("a", "m1", "\"needle one\""),
    "{",
    "[]",
    "{\"payload\":1}",
    user("b", "m2", "\"needle \u{FFFD} two\"")]
  done = folded(phrase("needle"), lines)
  assert done.scan.candidates.size == 2 and done.scan.errors.size == 0
  assert done.scan.warnings.size == 4
  malformed = done.scan.warnings.get("a malformed JSON record was skipped")
  assert malformed is Some(first)
  assert first.count == 1 and first.line == 2
end

test "a repeated UUID in one file keeps the first record and warns"
  done = folded(phrase("needle"),
    [user("a", "m1", "\"needle first\""), user("a", "m1", "\"needle second\"")])
  assert done.scan.retained_blocks == 1 and done.scan.warnings.size == 1
  other = folded_line(start_file(done.scan, phrase("needle"), "two.jsonl"),
    user("a", "m1", "\"needle again\""))
  assert other.scan.retained_blocks == 2
end

test "tool references are searchable by name and images and documents are excluded"
  parts = "[{\"type\":\"tool_result\",\"tool_use_id\":\"t\",\"content\":[{\"type\":\"tool_reference\",\"tool_name\":\"ToolSearch\"},{\"type\":\"image\"},{\"type\":\"document\"}]}]"
  done = folded(phrase("toolsearch"), [user("a", "m1", parts)])
  assert done.scan.candidates.size == 1 and done.scan.warnings.size == 0
  assert done.scan.candidates.values.first is Some(hit)
  assert hit.blocks.first is Some(block)
  assert block.label == "tool result t part 0" and block.excerpt == "ToolSearch"
end

test "an unsupported block is skipped with a warning and its siblings still match"
  blocks = "[{\"type\":\"future_block\"},{\"type\":\"text\",\"text\":\"needle\",\"apiBlockIndex\":4}]"
  done = folded(phrase("needle"), [user("a", "m1", blocks)])
  assert done.scan.candidates.size == 1
  assert done.scan.warnings.has?("a content block of unsupported type future_block was skipped")
  assert done.scan.candidates.values.first is Some(hit)
  assert hit.blocks.first is Some(block)
  assert block.local_index == 1 and block.api_index == Some(4)
end

test "unknown bookkeeping is counted and unknown conversation-shaped types warn"
  done = folded(phrase("needle"),
    ["{\"type\":\"progress\",\"text\":\"needle\"}",
    "{\"type\":\"future\",\"message\":{\"role\":\"user\",\"content\":\"needle\"}}"])
  assert done.scan.ignored.get("progress") == Some(1) and done.scan.candidates.size == 0
  assert done.scan.warnings.size == 1 and done.scan.errors.size == 0
end

test "candidate and block retention limits are errors"
  var full = empty_scan()
  full.retained_blocks = 100_000
  capped = folded_line(start_file(full, phrase("needle"), "x.jsonl"), user("a", "m", "\"needle\""))
  assert capped.scan.errors.size == 1 and capped.scan.candidates.size == 0
end

verified: types, contracts, tests (7), property (0 seeds), sim (not run)
          proven: not run
