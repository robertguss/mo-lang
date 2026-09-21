module Parse
expose FileFold, start_file, folded_line

use Limits{line_bytes, file_records, records, messages, blocks, diagnostics}
use Model{BlockKind, Block, Message, Seen, Issue, Scan, empty_scan}

intent "Decode admitted JSONL records, conservatively diagnose unsupported conversation shapes, and group messages file-locally without losing block provenance."

struct FileFold
  scan: Scan
  seen: Map(String, Seen)
  path: String
  lines: UInt64
  file_records: UInt64
  bytes: UInt64
  admitted: UInt64
  stopped: Bool
end

struct ParsedBlocks
  scan: Scan
  blocks: List(Block)
end

struct ConversationInput
  path: String
  line: UInt64
  kind: String
  session: String
  at: Option(Time)
end

struct Identity
  kind: String
  value: String
  label: String
end

struct ResultPlace
  path: String
  line: UInt64
  local: UInt64
  api: Option(UInt64)
  id: String
end

fn start_file(scan: Scan, path: String, admitted: UInt64) : FileFold
  FileFold(scan: scan, seen: Map.new(), path: path, lines: 0, file_records: 0, bytes: 0,
    admitted: admitted, stopped: false)
end

# fold_lines cannot stop the underlying synchronous read. Once stopped, this callback only counts
# physical lines; it does not decode or retain more records.
fn folded_line(state: FileFold, line: String) : FileFold
  var next = state
  next.lines += 1
  next.bytes = next.bytes.saturating_add(line.byte_size + 1)
  replacement = line.contains?("\u{FFFD}")
  if next.stopped
    return next
  end
  if line.byte_size > line_bytes()
    next.scan = problem(next.scan, next.path, next.lines, "a JSONL line exceeds 1 MiB")
    next.stopped = true
    return next
  end
  # fold_lines replaces each malformed byte with the three-byte UTF-8 U+FFFD spelling. When that
  # happened, transformed byte size cannot prove file growth; the U+FFFD diagnostic below already
  # refuses complete success for both malformed input and a genuine replacement character.
  if !replacement and next.bytes > next.admitted.saturating_add(1)
    next.scan = problem(next.scan, next.path, next.lines,
      "the file grew after size admission; results use only the admitted prefix")
    next.stopped = true
    return next
  end
  if !file_record_admitted?(next.file_records)
    next.scan = problem(next.scan, next.path, next.lines, "the file exceeds 200000 records")
    next.stopped = true
    return next
  end
  if !record_admitted?(next.scan.records)
    next.scan = problem(next.scan, next.path, next.lines, "the search exceeds 1000000 records")
    next.stopped = true
    return next
  end
  next.file_records += 1
  next.scan.records += 1
  # U+FFFD can be genuine input or fold_lines' replacement for malformed UTF-8. The API does not
  # expose which, so complete success is refused in either case.
  if replacement
    next.scan = problem(next.scan, next.path, next.lines,
      "U+FFFD is present; fold_lines cannot distinguish it from replaced invalid UTF-8")
  end
  case Json.decode(line)
    Ok(payload):
      deduped = accepted_uuid(next, payload)
      next = deduped.0
      if deduped.1
        next.scan = decoded_record(next.scan, next.path, next.lines, payload)
      end
    Error(_):
      next.scan = problem(next.scan, next.path, next.lines, "malformed JSON record")
  end
  next
end

# The bool says whether to process this physical record.
fn accepted_uuid(state: FileFold, payload: Json) : (FileFold, Bool)
  var next = state
  fields = case payload
    Object(given): given
    String(_) | Array(_) | Number(_) | Bool(_) | Null:
      return (next, true)
  end
  case fields.get("uuid")
    None: (next, true)
    Some(String(uuid)):
      case next.seen.get(uuid)
        None:
          next.seen = next.seen.set(uuid, Seen(payload: payload, line: next.lines))
          (next, true)
        Some(prior):
          if prior.payload == payload
            (next, false)
          else
            next.scan = problem(next.scan, next.path, next.lines,
              "UUID #{uuid} conflicts with line #{prior.line}")
            (next, false)
          end
      end
    Some(_): (next, true)
  end
end

fn decoded_record(scan: Scan, path: String, line: UInt64, payload: Json) : Scan
  fields = case payload
    Object(given): given
    String(_) | Array(_) | Number(_) | Bool(_) | Null:
      return problem(scan, path, line, "top-level JSON record is not an object")
  end
  kind = case fields.get("type")
    Some(String(name)): name
    None | Some(Object(_)) | Some(Array(_)) | Some(Number(_)) | Some(Bool(_)) | Some(Null):
      return problem(scan, path, line, "top-level record type is missing or not a string")
  end
  if kind != "user" and kind != "assistant"
    if fields.get("message") is Some(Object(_))
      return problem(scan, path, line,
        "unknown type #{kind} has a conversation-shaped message")
    end
    return unknown(scan, kind)
  end
  conversation(scan, path, line, kind, fields)
end

fn conversation(scan: Scan, path: String, line: UInt64, kind: String,
  fields: Map(String, Json)) : Scan
  var next = scan
  if marked?(fields, "isMeta") or marked?(fields, "isCompactSummary") or marked?(fields, "isApiErrorMessage")
    return next
  end
  if fields.get("uuid") is Some(value)
    if !(value is String(_))
      next = problem(next, path, line, "conversation uuid is not a string")
    end
  end
  session = session_of(next, path, line, fields)
  next = session.0
  timed = timestamp_of(next, path, line, fields)
  next = timed.0
  input = ConversationInput(path: path, line: line, kind: kind, session: session.1, at: timed.1)
  message_record(next, input, fields)
end

fn session_of(scan: Scan, path: String, line: UInt64,
  fields: Map(String, Json)) : (Scan, String)
  case fields.get("sessionId")
    Some(String(id)): (scan, id)
    None: (scan, "")
    Some(Object(_)) | Some(Array(_)) | Some(Number(_)) | Some(Bool(_)) | Some(Null):
      (problem(scan, path, line, "conversation sessionId is not a string"), "")
  end
end


fn timestamp_of(scan: Scan, path: String, line: UInt64,
  fields: Map(String, Json)) : (Scan, Option(Time))
  case fields.get("timestamp")
    Some(String(text)):
      case Time.parse(text)
        Some(parsed): (scan, Some(parsed))
        None: (problem(scan, path, line,
          "conversation timestamp is not supported RFC 3339"), None)
      end
    None: (scan, None)
    Some(Object(_)) | Some(Array(_)) | Some(Number(_)) | Some(Bool(_)) | Some(Null):
      (problem(scan, path, line, "conversation timestamp is not a string"), None)
  end
end

fn message_record(scan: Scan, input: ConversationInput,
  fields: Map(String, Json)) : Scan
  message_fields = case fields.get("message")
    Some(Object(given)): given
    None | Some(String(_)) | Some(Array(_)) | Some(Number(_)) | Some(Bool(_)) | Some(Null):
      return problem(scan, input.path, input.line, "conversation message is not an object")
  end
  role = case message_fields.get("role")
    Some(String(name)): name
    None | Some(Object(_)) | Some(Array(_)) | Some(Number(_)) | Some(Bool(_)) | Some(Null):
      return problem(scan, input.path, input.line, "conversation message role is not a string")
  end
  if role != input.kind
    return problem(scan, input.path, input.line, "top-level type and message role disagree")
  end
  identified = identity_of(scan, input.path, input.line, message_fields)
  parsed = case message_fields.get("content")
    Some(String(text)):
      ParsedBlocks(scan: identified.0,
        blocks: [conversation_block(role, text, input.path, input.line, 0, None)])
    Some(Array(items)): blocks_of(identified.0, role, input.path, input.line, items)
    None | Some(Object(_)) | Some(Number(_)) | Some(Bool(_)) | Some(Null):
      return problem(identified.0, input.path, input.line,
        "conversation content is neither text nor a block array")
  end
  retain_message(parsed.scan, input, identified.1, parsed.blocks)
end

fn identity_of(scan: Scan, path: String, line: UInt64,
  fields: Map(String, Json)) : (Scan, Identity)
  case fields.get("id")
    Some(String(value)): (scan, Identity(kind: "provided", value: value, label: value))
    None:
      label = "physical:#{line}"
      (scan, Identity(kind: "physical", value: "#{line}", label: label))
    Some(Object(_)) | Some(Array(_)) | Some(Number(_)) | Some(Bool(_)) | Some(Null):
      label = "physical:#{line}"
      (problem(scan, path, line, "message id is not a string"),
        Identity(kind: "physical", value: "#{line}", label: label))
  end
end

fn retain_message(scan: Scan, input: ConversationInput, identity: Identity,
  parsed: List(Block)) : Scan
  var next = scan
  return next if parsed.size == 0
  session_key = if input.session == "": "file:#{input.path}" else: "session:#{input.session}"
  session_label = if input.session == "": "(missing session id in #{input.path})" else: input.session
  key = Json.encode((input.path, session_key, input.kind, identity.kind, identity.value))
  existing = next.messages.get(key)
  if existing is None and !message_admitted?(next.messages.size)
    return problem(next, input.path, input.line, "more than 100000 logical messages would be retained")
  end
  room = blocks().saturating_sub(next.retained_blocks)
  kept = parsed.take(room)
  if kept.size < parsed.size
    next = problem(next, input.path, input.line,
      "more than 500000 searchable blocks would be retained")
  end
  next.retained_blocks += kept.size
  record_at = if kept.any?(fn(block) block.kind == Conversation end): input.at else: None
  case existing
    Some(before):
      merged = Message(key: key, session_key: session_key, session_label: session_label,
        role: input.kind, id: identity.label, path: input.path, first_line: before.first_line,
        conversation_at: later(before.conversation_at, record_at),
        blocks: before.blocks.concat(kept))
      next.messages = next.messages.set(key, merged)
    None:
      made = Message(key: key, session_key: session_key, session_label: session_label,
        role: input.kind, id: identity.label, path: input.path, first_line: input.line,
        conversation_at: record_at, blocks: kept)
      next.messages = next.messages.set(key, made)
  end
  next
end

fn blocks_of(scan: Scan, role: String, path: String, line: UInt64,
  items: List(Json)) : ParsedBlocks
  var parsed = ParsedBlocks(scan: scan, blocks: [])
  for pair in items.enumerate
    one = block_of(parsed.scan, role, path, line, pair.0, pair.1)
    parsed.scan = one.scan
    parsed.blocks = parsed.blocks.concat(one.blocks)
  end
  parsed
end

fn block_of(scan: Scan, role: String, path: String, line: UInt64, local: UInt64,
  value: Json) : ParsedBlocks
  fields = case value
    Object(given): given
    String(_) | Array(_) | Number(_) | Bool(_) | Null:
      return ParsedBlocks(scan: problem(scan, path, line,
        "content block #{local} is not an object"), blocks: [])
  end
  kind = case fields.get("type")
    Some(String(name)): name
    None | Some(Object(_)) | Some(Array(_)) | Some(Number(_)) | Some(Bool(_)) | Some(Null):
      return ParsedBlocks(scan: problem(scan, path, line,
        "content block #{local} has no string type"), blocks: [])
  end
  api = api_index(scan, path, line, local, fields)
  next = api.0
  case kind
    "text":
      case fields.get("text")
        Some(String(text)):
          ParsedBlocks(scan: next,
            blocks: [conversation_block(role, text, path, line, local, api.1)])
        None | Some(Object(_)) | Some(Array(_)) | Some(Number(_)) | Some(Bool(_)) | Some(Null):
          ParsedBlocks(scan: problem(next, path, line,
            "text block #{local} has no string text"), blocks: [])
      end
    "thinking" | "redacted_thinking" | "image": ParsedBlocks(scan: next, blocks: [])
    "tool_use": tool_use(next, path, line, local, api.1, fields)
    "tool_result": tool_result(next, path, line, local, api.1, fields)
    _:
      ParsedBlocks(scan: problem(next, path, line,
        "unsupported conversation block type #{kind}"), blocks: [])
  end
end

fn conversation_block(role: String, text: String, path: String, line: UInt64,
  local: UInt64, api: Option(UInt64)) : Block
  Block(kind: Conversation, label: "#{role} text", text: text, path: path, line: line,
    local_index: local, api_index: api)
end

fn tool_use(scan: Scan, path: String, line: UInt64, local: UInt64,
  api: Option(UInt64), fields: Map(String, Json)) : ParsedBlocks
  name = case fields.get("name")
    Some(String(value)): value
    None | Some(Object(_)) | Some(Array(_)) | Some(Number(_)) | Some(Bool(_)) | Some(Null):
      return ParsedBlocks(scan: problem(scan, path, line,
        "tool_use block #{local} has no string name"), blocks: [])
  end
  input = case fields.get("input")
    Some(value): value
    None:
      return ParsedBlocks(scan: problem(scan, path, line,
        "tool_use block #{local} has no input"), blocks: [])
  end
  block = Block(kind: Tool, label: "tool #{name} arguments", text: Json.encode(input),
    path: path, line: line, local_index: local, api_index: api)
  ParsedBlocks(scan: scan, blocks: [block])
end

fn tool_result(scan: Scan, path: String, line: UInt64, local: UInt64,
  api: Option(UInt64), fields: Map(String, Json)) : ParsedBlocks
  id = case fields.get("tool_use_id")
    Some(String(value)): value
    None: "unknown"
    Some(_):
      return ParsedBlocks(scan: problem(scan, path, line,
        "tool_result block #{local} has a non-string tool_use_id"), blocks: [])
  end
  case fields.get("content")
    Some(String(text)):
      block = Block(kind: Tool, label: "tool result #{id}", text: text, path: path,
        line: line, local_index: local, api_index: api)
      ParsedBlocks(scan: scan, blocks: [block])
    Some(Array(items)):
      place = ResultPlace(path: path, line: line, local: local, api: api, id: id)
      result_parts(scan, place, items)
    None | Some(Object(_)) | Some(Number(_)) | Some(Bool(_)) | Some(Null):
      ParsedBlocks(scan: problem(scan, path, line,
        "tool_result block #{local} has unsupported content"), blocks: [])
  end
end

fn result_parts(scan: Scan, place: ResultPlace, items: List(Json)) : ParsedBlocks
  var parsed = ParsedBlocks(scan: scan, blocks: [])
  for pair in items.enumerate
    one = result_part(parsed.scan, place, pair.0, pair.1)
    parsed.scan = one.scan
    parsed.blocks = parsed.blocks.concat(one.blocks)
  end
  parsed
end

fn result_part(scan: Scan, place: ResultPlace, part: UInt64,
  value: Json) : ParsedBlocks
  fields = case value
    Object(given): given
    String(_) | Array(_) | Number(_) | Bool(_) | Null:
      return ParsedBlocks(scan: problem(scan, place.path, place.line,
        "tool result part #{part} is not an object"), blocks: [])
  end
  case fields.get("type")
    Some(String("text")):
      case fields.get("text")
        Some(String(text)):
          block = Block(kind: Tool, label: "tool result #{place.id} part #{part}", text: text,
            path: place.path, line: place.line, local_index: place.local,
            api_index: place.api)
          ParsedBlocks(scan: scan, blocks: [block])
        None | Some(Object(_)) | Some(Array(_)) | Some(Number(_)) | Some(Bool(_)) | Some(Null):
          ParsedBlocks(scan: problem(scan, place.path, place.line,
            "tool result text part #{part} has no string text"), blocks: [])
      end
    Some(String("image")): ParsedBlocks(scan: scan, blocks: [])
    Some(String(kind)):
      ParsedBlocks(scan: problem(scan, place.path, place.line,
        "unsupported tool result part type #{kind}"), blocks: [])
    None | Some(Object(_)) | Some(Array(_)) | Some(Number(_)) | Some(Bool(_)) | Some(Null):
      ParsedBlocks(scan: problem(scan, place.path, place.line,
        "tool result part #{part} has no string type"), blocks: [])
  end
end

# Returns the possibly diagnosed scan and the explicit API block index. A local array index is
# never substituted for an absent API index.
fn api_index(scan: Scan, path: String, line: UInt64, local: UInt64,
  fields: Map(String, Json)) : (Scan, Option(UInt64))
  case fields.get("apiBlockIndex")
    None: (scan, None)
    Some(value):
      case value.to_i64
        Some(n):
          if n >= 0
            (scan, Some(n.to_u64))
          else
            (problem(scan, path, line, "apiBlockIndex on block #{local} is negative"), None)
          end
        None: (problem(scan, path, line,
          "apiBlockIndex on block #{local} is not a whole integer"), None)
      end
  end
end

fn marked?(fields: Map(String, Json), name: String) : Bool
  fields.get(name) == Some(Bool(value: true))
end

fn file_record_admitted?(count: UInt64) : Bool
  count < file_records()
end

fn record_admitted?(count: UInt64) : Bool
  count < records()
end

fn message_admitted?(count: UInt64) : Bool
  count < messages()
end

fn later(a: Option(Time), b: Option(Time)) : Option(Time)
  case (a, b)
    (Some(left), Some(right)): Some(max_of(left, right))
    (Some(left), None): Some(left)
    (None, Some(right)): Some(right)
    (None, None): None
  end
end

fn unknown(scan: Scan, kind: String) : Scan
  var next = scan
  key = if kind.size <= 128: kind else: "#{kind.slice(0, 128)}..."
  if next.unknown_kinds.has?(key)
    next.unknown_kinds = next.unknown_kinds.update(key, 0, fn(n) n.saturating_add(1) end)
  else
    if next.unknown_kinds.size < diagnostics().saturating_sub(1)
      next.unknown_kinds = next.unknown_kinds.set(key, 1)
    else
      next.unknown_kinds = next.unknown_kinds.update("<additional kinds>", 0,
        fn(n) n.saturating_add(1) end)
    end
  end
  next
end

fn problem(scan: Scan, path: String, line: UInt64, detail: String) : Scan
  var next = scan
  next.incomplete = true
  if next.issues.size < diagnostics()
    next.issues = next.issues.push(Issue(path: path, line: line, detail: detail))
  end
  next
end

test "decoded UUID equality ignores object order and JSON spelling"
  first = "{\"type\":\"user\",\"uuid\":\"u\",\"message\":{\"role\":\"user\",\"id\":\"m\",\"content\":\"a\"}}"
  same = "{\"message\":{\"content\":\"\\u0061\",\"id\":\"m\",\"role\":\"user\"},\"uuid\":\"u\",\"type\":\"user\"}"
  one = folded_line(start_file(empty_scan(), "one.jsonl", 10_000), first)
  two = folded_line(one, same)
  assert two.scan.messages.size == 1 and !two.scan.incomplete and two.scan.records == 2
end

test "file-local UUID state resets and malformed middle input retains neighboring messages"
  before = "{\"type\":\"user\",\"uuid\":\"u\",\"message\":{\"role\":\"user\",\"id\":\"a\",\"content\":\"before\"}}"
  after = "{\"type\":\"user\",\"uuid\":\"v\",\"message\":{\"role\":\"user\",\"id\":\"b\",\"content\":\"after\"}}"
  one = folded_line(start_file(empty_scan(), "one.jsonl", 10_000), before)
  broken = folded_line(one, "{")
  kept = folded_line(broken, after)
  assert kept.scan.messages.size == 2 and kept.scan.incomplete and kept.scan.records == 3
  other = folded_line(start_file(kept.scan, "two.jsonl", 10_000), before)
  assert other.scan.messages.size == 3
end

test "replacement characters and conflicting payloads preserve first results but are incomplete"
  first = "{\"type\":\"user\",\"uuid\":\"u\",\"message\":{\"role\":\"user\",\"id\":\"m\",\"content\":\"kept\"}}"
  conflict = "{\"type\":\"user\",\"uuid\":\"u\",\"message\":{\"role\":\"user\",\"id\":\"m\",\"content\":\"changed\"}}"
  one = folded_line(start_file(empty_scan(), "one.jsonl", 10_000), first)
  two = folded_line(one, conflict)
  marked = folded_line(two, "{\"type\":\"progress\",\"text\":\"\u{FFFD}\"}")
  assert marked.scan.messages.size == 1 and marked.scan.incomplete
  assert marked.scan.unknown_kinds.get("progress") == Some(1)
end

test "production per-file total-record and retained-block counters refuse the next value"
  var per_file = start_file(empty_scan(), "one.jsonl", 10_000)
  per_file.file_records = 200_000
  assert folded_line(per_file, "{}").scan.incomplete
  var total_scan = empty_scan()
  total_scan.records = 1_000_000
  assert folded_line(start_file(total_scan, "two.jsonl", 10_000), "{}").scan.incomplete
  var block_scan = empty_scan()
  block_scan.retained_blocks = 500_000
  record = "{\"type\":\"user\",\"message\":{\"role\":\"user\",\"id\":\"m\",\"content\":\"kept\"}}"
  capped = folded_line(start_file(block_scan, "three.jsonl", 10_000), record).scan
  assert capped.incomplete and capped.retained_blocks == 500_000
end

test "production record and message admission predicates differ at each boundary"
  assert file_record_admitted?(199_999) and !file_record_admitted?(200_000)
  assert record_admitted?(999_999) and !record_admitted?(1_000_000)
  assert message_admitted?(99_999) and !message_admitted?(100_000)
end
