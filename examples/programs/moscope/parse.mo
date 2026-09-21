module Moscope.Parse
expose FileFold, start_file, folded_line

use Moscope.Limits{line_bytes, file_records, records, messages, blocks, diagnostics,
  process_time}
use Moscope.Model{BlockKind, Block, Message, Seen, Issue, Scan}

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
  clock: Clock
  started: Time
end

struct ParsedBlocks
  scan: Scan
  blocks: List(Block)
end

fn start_file(scan: Scan, path: String, admitted: UInt64, clock: Clock, started: Time) : FileFold
  FileFold(scan: scan, seen: Map.new(), path: path, lines: 0, file_records: 0, bytes: 0,
    admitted: admitted, stopped: false, clock: clock, started: started)
end

# fold_lines cannot stop the underlying synchronous read. Once stopped, this callback only counts
# physical lines; it does not decode or retain more records.
fn folded_line(state: FileFold, line: String) : FileFold
  var next = state
  next.lines += 1
  next.bytes = next.bytes.saturating_add(line.byte_size + 1)
  if next.stopped
    return next
  end
  if next.clock.now >= next.started + process_time()
    next.scan = problem(next.scan, next.path, next.lines, "the 60 second processing deadline was exceeded")
    next.stopped = true
    return next
  end
  if line.byte_size > line_bytes()
    next.scan = problem(next.scan, next.path, next.lines, "a JSONL line exceeds 1 MiB")
    next.stopped = true
    return next
  end
  if next.bytes > next.admitted.saturating_add(1)
    next.scan = problem(next.scan, next.path, next.lines,
      "the file grew after size admission; results use only the admitted prefix")
    next.stopped = true
    return next
  end
  if next.file_records >= file_records()
    next.scan = problem(next.scan, next.path, next.lines, "the file exceeds 200000 records")
    next.stopped = true
    return next
  end
  if next.scan.records >= records()
    next.scan = problem(next.scan, next.path, next.lines, "the search exceeds 1000000 records")
    next.stopped = true
    return next
  end
  next.file_records += 1
  next.scan.records += 1
  # U+FFFD can be genuine input or fold_lines' replacement for malformed UTF-8. The API does not
  # expose which, so complete success is refused in either case.
  if line.contains?("\u{FFFD}")
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
    _: return (next, true)
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
    _: return unknown(scan, "<non-object>")
  end
  kind = case fields.get("type")
    Some(String(name)): name
    _: return unknown(scan, "<missing-or-non-string>")
  end
  if kind != "user" and kind != "assistant"
    return unknown(scan, kind)
  end
  conversation(scan, path, line, kind, fields)
end

fn conversation(scan: Scan, path: String, line: UInt64, kind: String,
  fields: Map(String, Json)) : Scan
  var next = scan
  if marked?(fields, "isMeta") or marked?(fields, "isCompactSummary") or
    marked?(fields, "isApiErrorMessage")
    return next
  end
  if fields.get("uuid") is Some(value)
    if !(value is String(_))
      next = problem(next, path, line, "conversation uuid is not a string")
    end
  end
  session = case fields.get("sessionId")
    Some(String(id)): id
    None: ""
    Some(_):
      next = problem(next, path, line, "conversation sessionId is not a string")
      ""
  end
  at = case fields.get("timestamp")
    Some(String(text)):
      case Time.parse(text)
        Some(parsed): Some(parsed)
        None:
          next = problem(next, path, line, "conversation timestamp is not supported RFC 3339")
          None
      end
    None: None
    Some(_):
      next = problem(next, path, line, "conversation timestamp is not a string")
      None
  end
  message_fields = case fields.get("message")
    Some(Object(given)): given
    _:
      return problem(next, path, line, "conversation message is not an object")
  end
  role = case message_fields.get("role")
    Some(String(name)): name
    _:
      return problem(next, path, line, "conversation message role is not a string")
  end
  if role != kind
    return problem(next, path, line, "top-level type and message role disagree")
  end
  id = case message_fields.get("id")
    Some(String(value)): value
    None: "physical:#{line}"
    Some(_):
      next = problem(next, path, line, "message id is not a string")
      "physical:#{line}"
  end
  parsed = case message_fields.get("content")
    Some(String(text)):
      ParsedBlocks(scan: next, blocks: [conversation_block(role, text, path, line, 0, None)])
    Some(Array(items)): blocks_of(next, role, path, line, items)
    _:
      return problem(next, path, line, "conversation content is neither text nor a block array")
  end
  next = parsed.scan
  return next if parsed.blocks.size == 0
  session_key = if session == "": "file:#{path}" else: "session:#{session}"
  session_label = if session == "": "(missing session id in #{path})" else: session
  key = Json.encode((path, session_key, role, id))
  existing = next.messages.get(key)
  if existing is None and next.messages.size >= messages()
    return problem(next, path, line, "more than 100000 logical messages would be retained")
  end
  room = blocks().saturating_sub(next.retained_blocks)
  kept = parsed.blocks.take(room)
  if kept.size < parsed.blocks.size
    next = problem(next, path, line, "more than 500000 searchable blocks would be retained")
  end
  next.retained_blocks += kept.size
  record_at = if kept.any?(fn(block) block.kind == Conversation end): at else: None
  case existing
    Some(before):
      merged = Message(key: key, session_key: session_key, session_label: session_label,
        role: role, id: id, path: path, first_line: before.first_line,
        conversation_at: later(before.conversation_at, record_at),
        blocks: before.blocks.concat(kept))
      next.messages = next.messages.set(key, merged)
    None:
      made = Message(key: key, session_key: session_key, session_label: session_label,
        role: role, id: id, path: path, first_line: line, conversation_at: record_at,
        blocks: kept)
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
    _:
      return ParsedBlocks(scan: problem(scan, path, line,
        "content block #{local} is not an object"), blocks: [])
  end
  kind = case fields.get("type")
    Some(String(name)): name
    _:
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
        _:
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
    _:
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
    Some(Array(items)): result_parts(scan, path, line, local, api, id, items)
    _:
      ParsedBlocks(scan: problem(scan, path, line,
        "tool_result block #{local} has unsupported content"), blocks: [])
  end
end

fn result_parts(scan: Scan, path: String, line: UInt64, local: UInt64,
  api: Option(UInt64), id: String, items: List(Json)) : ParsedBlocks
  var next = scan
  var kept: List(Block) = []
  for pair in items.enumerate
    case pair.1
      Object(fields):
        case fields.get("type")
          Some(String("text")):
            case fields.get("text")
              Some(String(text)):
                kept = kept.push(Block(kind: Tool, label: "tool result #{id} part #{pair.0}",
                  text: text, path: path, line: line, local_index: local, api_index: api))
              _:
                next = problem(next, path, line,
                  "tool result text part #{pair.0} has no string text")
            end
          Some(String(kind)):
            if kind != "image"
              next = problem(next, path, line, "unsupported tool result part type #{kind}")
            end
          _:
            next = problem(next, path, line,
              "tool result part #{pair.0} has no string type")
        end
      _:
        next = problem(next, path, line, "tool result part #{pair.0} is not an object")
    end
  end
  ParsedBlocks(scan: next, blocks: kept)
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
