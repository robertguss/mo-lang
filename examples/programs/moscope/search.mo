module Search
expose report, ascii_lower, query_terms, safe

use Limits{results, diagnostics, excerpt, output_bytes, process_time}
use Model{Mode, Options, BlockKind, Block, Message, Issue, Scan, Hit, Session, Report}

intent "Match eligible blocks with ASCII-only folding, order sessions by all eligible conversation activity, and render bounded terminal-safe plain text."

struct Searched
  scan: Scan
  hits: List(Hit)
end

struct Render
  text: String
  truncated: Bool
end

fn report(scan: Scan, options: Options, clock: Clock, started: Time) : Report
  found = searched(scan, options, clock, started)
  sessions = sessions_of(found.scan.messages.values, found.hits)
  var final_scan = found.scan
  var rendered = Render(text: "", truncated: false)
  var deadline_hit = false
  for session in sessions
    if clock.now >= started + process_time()
      final_scan = problem(final_scan, "<search>", 0,
        "the 60 second processing deadline was exceeded")
      deadline_hit = true
      break
    end
    rendered = append(rendered, session_heading(session))
    if rendered.truncated
      break
    end
    for hit in session.hits.sort_by(fn(one)
      (one.entry.path, one.entry.first_line, one.entry.role, one.entry.id)
    end)
      if clock.now >= started + process_time()
        final_scan = problem(final_scan, "<search>", 0,
          "the 60 second processing deadline was exceeded")
        deadline_hit = true
        break
      end
      rendered = render_hit(rendered, hit)
      if rendered.truncated
        break
      end
    end
    if deadline_hit or rendered.truncated
      break
    end
  end
  summary = if found.hits.size == 0: "No matches.\n" else: "#{found.hits.size} matching messages.\n"
  rendered = append(rendered, summary)
  if rendered.truncated
    final_scan = problem(final_scan, "<output>", 0, "rendered output exceeds 8 MiB")
  end
  remaining = output_bytes().saturating_sub(rendered.text.byte_size)
  diagnosed = diagnostics_text(final_scan, remaining)
  Report(text: rendered.text, diagnostics: diagnosed.text, matches: found.hits.size,
    incomplete: final_scan.incomplete or diagnosed.truncated)
end

fn searched(scan: Scan, options: Options, clock: Clock, started: Time) : Searched
  var result = Searched(scan: scan, hits: [])
  lowered = ascii_lower(options.query)
  words = query_terms(options.query)
  for entry in scan.messages.values.sort_by(fn(one) one.key end)
    if clock.now >= started + process_time()
      result.scan = problem(result.scan, "<search>", 0,
        "the 60 second processing deadline was exceeded")
      break
    end
    eligible = entry.blocks.filter(fn(block)
      block.kind == Conversation or (options.include_tools and block.kind == Tool)
    end)
    shown = case options.mode
      Phrase: eligible.filter(fn(block) ascii_lower(searchable(block)).contains?(lowered) end)
      AllWords:
        if words.all?(fn(word)
          eligible.any?(fn(block)
            ascii_lower(searchable(block)).contains?(word)
          end)
        end)
          eligible
        else
          []
        end
    end
    if shown.size > 0
      if !result_admitted?(result.hits.size)
        result.scan = problem(result.scan, entry.path, entry.first_line,
          "search exceeds 10000 matching logical messages")
        break
      end
      result.hits = result.hits.push(Hit(entry: entry, blocks: shown))
    end
  end
  result
end

fn searchable(block: Block) : String
  if block.kind == Tool: "#{block.label}\n#{block.text}" else: block.text
end

fn sessions_of(messages: List(Message), hits: List(Hit)) : List(Session)
  labels = messages.reduce(Map.new(),
    fn(known, entry) known.set(entry.session_key, entry.session_label) end)
  latest = messages.reduce(Map.new(), fn(known, entry)
    known.set(entry.session_key, later(known.get(entry.session_key) or None, entry.conversation_at))
  end)
  grouped = hits.reduce(Map.new(),
    fn(known, hit) known.update(hit.entry.session_key, [], fn(before) before.push(hit) end) end)
  built = grouped.entries.map(fn(pair)
    Session(key: pair.0, label: labels.get(pair.0) or pair.0, latest: latest.get(pair.0) or None,
      hits: pair.1)
  end)
  timed = built.filter(fn(one)
    one.latest is Some(_)
  end).sort_by(fn(one)
    (one.label, one.key)
  end).sort_by_desc(fn(one) one.latest or Time.from_parts(1970, 1, 1, 0, 0, 0) end)
  missing = built.filter(fn(one) one.latest is None end).sort_by(fn(one) (one.label, one.key) end)
  timed.concat(missing)
end

fn session_heading(session: Session) : String
  latest = case session.latest
    Some(at): at.to_iso8601
    None: "timestamp missing"
  end
  "Session #{safe_prefix(session.label, 256)} — latest #{latest}\n"
end

fn render_hit(rendered: Render, hit: Hit) : Render
  var next = append(rendered,
    "  #{safe_prefix(hit.entry.role, 256)} message #{safe_prefix(hit.entry.id, 256)}\n")
  for block in hit.blocks
    if next.truncated
      break
    end
    api = case block.api_index
      Some(index): " apiBlockIndex=#{index}"
      None: ""
    end
    next = append(next,
      "    #{safe_prefix(block.path, 512)}:#{block.line} #{safe_prefix(block.label, 256)} content[#{block.local_index}]#{api}\n")
    if next.truncated
      break
    end
    next = append(next, "      #{bounded_excerpt(block.text)}\n")
  end
  next
end

fn bounded_excerpt(text: String) : String
  safe_prefix(text, excerpt())
end

fn diagnostics_text(scan: Scan, limit: UInt64) : Render
  var rendered = Render(text: "", truncated: false)
  if scan.incomplete
    rendered = incomplete_text(rendered, scan, limit)
  end
  if !rendered.truncated
    rendered = notices_text(rendered, scan, limit)
  end
  if rendered.truncated
    sentinel = "moscope: incomplete: diagnostics exceed the 8 MiB rendered-output limit\n"
    if rendered.text.byte_size.saturating_add(sentinel.byte_size) <= limit
      rendered.text = "#{rendered.text}#{sentinel}"
    end
  end
  rendered
end

fn notices_text(rendered: Render, scan: Scan, limit: UInt64) : Render
  var next = rendered
  if scan.skipped_links > 0
    next = append_limit(next,
      "moscope: diagnostic: skipped #{scan.skipped_links} discovered symlinks\n", limit)
  end
  return next if next.truncated
  for pair in scan.unknown_kinds.entries.sort_by(fn(entry) entry.0 end)
    next = append_limit(next,
      "moscope: diagnostic: ignored #{pair.1} records of kind #{safe_prefix(pair.0, 256)}\n", limit)
    if next.truncated
      break
    end
  end
  next
end

fn incomplete_text(rendered: Render, scan: Scan, limit: UInt64) : Render
  var next = rendered
  output = scan.issues.filter(fn(issue)
    issue.path == "<output>" and issue.detail == "rendered output exceeds 8 MiB"
  end)
  other = scan.issues.filter(fn(issue)
    issue.path != "<output>" or issue.detail != "rendered output exceeds 8 MiB"
  end)
  for issue in output.concat(other)
    path = safe_prefix(issue.path, 512)
    location = if issue.line == 0: path else: "#{path}:#{issue.line}"
    next = append_limit(next,
      "moscope: incomplete: #{location}: #{safe_prefix(issue.detail, 512)}\n", limit)
    if next.truncated
      break
    end
  end
  if !next.truncated and scan.issues.size >= diagnostics()
    next = append_limit(next, "moscope: incomplete: diagnostic retention limit reached\n", limit)
  end
  next
end

fn append(rendered: Render, addition: String) : Render
  # Keep room for at least a short incomplete explanation after result truncation.
  append_limit(rendered, addition, output_bytes().saturating_sub(512))
end

fn append_limit(rendered: Render, addition: String, limit: UInt64) : Render
  return rendered if rendered.truncated
  if rendered.text.byte_size.saturating_add(addition.byte_size) > limit
    return Render(text: rendered.text, truncated: true)
  end
  Render(text: "#{rendered.text}#{addition}", truncated: false)
end

fn result_admitted?(count: UInt64) : Bool
  count < results()
end

# ASCII bytes A-Z fold; every non-ASCII byte is unchanged, so non-ASCII matching is exact.
fn ascii_lower(text: String) : String
  lowered = text.bytes.map(fn(byte)
    if byte >= 65 and byte <= 90: byte + 32 else: byte
  end)
  String.from_bytes(lowered) or ""
end

# ASCII space, tab, LF, vertical tab, form feed, and CR delimit terms.
fn query_terms(query: String) : List(String)
  spaced = query.bytes.map(fn(byte)
    if byte == 9 or byte == 10 or byte == 11 or byte == 12 or byte == 13: 32 else: byte
  end)
  normalized = String.from_bytes(spaced) or ""
  normalized.split(" ").filter(fn(word) word != "" end).map(fn(word) ascii_lower(word) end)
end

# Conservative terminal safety: printable ASCII passes (backslash is doubled); every control byte
# and every byte of non-ASCII UTF-8 is rendered as \xNN. Unicode controls therefore cannot pass.
fn safe(text: String) : String
  String.join(text.bytes.map(fn(byte)
    if byte >= 32 and byte <= 126 and byte != 92
      String.from_bytes([byte]) or ""
    else
      if byte == 92: "\\\\" else: "\\x#{hex(byte)}"
    end
  end), "")
end

fn safe_prefix(text: String, limit: UInt64) : String
  clipped = text.slice(0, min_of(text.size, limit))
  escaped = safe(clipped)
  if text.size > limit: "#{escaped}..." else: escaped
end

fn hex(byte: UInt8) : String
  digits = "0123456789ABCDEF"
  high = (byte / 16).to_u64
  low = (byte % 16).to_u64
  "#{digits.slice(high, high + 1)}#{digits.slice(low, low + 1)}"
end

fn later(a: Option(Time), b: Option(Time)) : Option(Time)
  case (a, b)
    (Some(left), Some(right)): Some(max_of(left, right))
    (Some(left), None): Some(left)
    (None, Some(right)): Some(right)
    (None, None): None
  end
end

fn problem(scan: Scan, path: String, line: UInt64, detail: String) : Scan
  var next = scan
  next.incomplete = true
  if next.issues.size < diagnostics()
    next.issues = next.issues.push(Issue(path: path, line: line, detail: detail))
  end
  next
end

test "ASCII folding leaves non-ASCII exact, and punctuation remains literal"
  assert ascii_lower("Connection REFUSED É") == "connection refused É"
  assert ascii_lower("É") != ascii_lower("é")
  assert ascii_lower("a.b[") == "a.b["
end

test "all-words uses exactly the six ASCII whitespace bytes"
  assert query_terms("  one\ttwo\nTHREE\u{000B}four\u{000C}five\r ") == ["one",
    "two",
    "three",
    "four",
    "five"]
end

test "safe output has no raw controls or non-ASCII bytes"
  assert safe("a\u{001B}[31m café\\z") == "a\\x1B[31m caf\\xC3\\xA9\\\\z"
end

test "terminal safety covers NUL DEL and bidi while doubling backslash"
  assert safe("A\\\u{0000}\u{007F}é") == "A\\\\\\x00\\x7F\\xC3\\xA9"
  assert safe("\u{202E}") == "\\xE2\\x80\\xAE"
end

test "excerpt boundaries and output admission differ on both sides of the limit"
  assert bounded_excerpt("x".repeat(239)).size == 239
  assert bounded_excerpt("x".repeat(240)).size == 240
  assert bounded_excerpt("x".repeat(241)).size == 243
  full = append_limit(Render(text: "1234", truncated: false), "5", 4)
  assert full.text == "1234" and full.truncated
  room = append_limit(Render(text: "1234", truncated: false), "5", 5)
  assert room.text == "12345" and !room.truncated
end

test "production result admission differs at the matching-message boundary"
  assert result_admitted?(9_999) and !result_admitted?(10_000)
end
