module Search
expose report, display

use Find{matcher_of, matches?}
use Limits{results, diagnostics, output_bytes}
use Model{Options, Matcher, Message, SessionInfo, Issue, Scan, Session, Report, failed}
use Term{safe_prefix, shell_word}

intent "Choose the candidates that match, order sessions by their latest eligible conversation, and render bounded terminal-safe plain text with resume hints and summarized diagnostics."

struct Chosen
  scan: Scan
  hits: List(Message)
end

# Output is gathered as parts and joined once, so rendering stays linear in its size.
struct Render
  parts: List(String)
  bytes: UInt64
  truncated: Bool
end

fn report(scan: Scan, options: Options) : Report
  chosen = matched(scan, matcher_of(options))
  var final_scan = chosen.scan
  var rendered = Render(parts: [], bytes: 0, truncated: false)
  for session in sessions_of(chosen.scan.sessions, chosen.hits, options.dir)
    rendered = render_session(rendered, session, options.dir)
    if rendered.truncated
      break
    end
  end
  count = chosen.hits.size
  summary = if count == 0: "No matches.\n" else: "#{counted(count, "matching message")}.\n"
  rendered = append(rendered, summary)
  if rendered.truncated
    final_scan.errors = failed(final_scan.errors, "", 0,
      "rendered output exceeds #{output_bytes()} bytes")
  end
  remaining = output_bytes().saturating_sub(rendered.bytes)
  diagnosed = diagnostics_text(final_scan, options, remaining)
  strict_failure = options.strict and final_scan.warnings.size > 0
  Report(text: String.join(rendered.parts, ""), diagnostics: String.join(diagnosed.parts, ""),
    matches: count, incomplete: final_scan.errors.size > 0 or diagnosed.truncated or strict_failure)
end

fn matched(scan: Scan, matcher: Matcher) : Chosen
  var chosen = Chosen(scan: scan, hits: [])
  for entry in scan.candidates.values.sort_by(fn(one) one.key end)
    if matches?(matcher, entry.found)
      if chosen.hits.size >= results()
        chosen.scan.errors = failed(chosen.scan.errors, entry.path, entry.first_line,
          "search exceeds #{results()} matching messages")
        break
      end
      chosen.hits = chosen.hits.push(entry)
    end
  end
  chosen
end

# Sessions with a latest time come first, newest first; ties and untimed sessions sort by label.
fn sessions_of(infos: Map(String, SessionInfo), hits: List(Message), dir: String) : List(Session)
  grouped = hits.reduce(Map.new(),
    fn(known, hit) known.update(hit.session_key, [], fn(before) before.push(hit) end) end)
  built = grouped.entries.map(fn(pair)
    fallback = SessionInfo(key: pair.0, path: pair.0, id: "", cwd: "", latest: None)
    Session(info: infos.get(pair.0) or fallback, hits: pair.1)
  end)
  timed = built.filter(fn(one)
    one.info.latest is Some(_)
  end).sort_by(fn(one)
    (label_of(one.info, dir), one.info.key)
  end).sort_by_desc(fn(one) one.info.latest or Time.from_parts(1970, 1, 1, 0, 0, 0) end)
  missing = built.filter(fn(one)
    one.info.latest is None
  end).sort_by(fn(one) (label_of(one.info, dir), one.info.key) end)
  timed.concat(missing)
end

fn render_session(rendered: Render, session: Session, dir: String) : Render
  var next = append(rendered, heading(session.info, dir))
  next = append(next, resume_line(session.info))
  for hit in session.hits.sort_by(fn(one) (one.path, one.first_line, one.role, one.id) end)
    if next.truncated
      break
    end
    next = render_hit(next, hit, dir)
  end
  next
end

fn label_of(info: SessionInfo, dir: String) : String
  if info.id == "": "(missing session id in #{display(dir, info.path)})" else: info.id
end

fn heading(info: SessionInfo, dir: String) : String
  latest = case info.latest
    Some(at): at.to_iso8601
    None: "timestamp missing"
  end
  "Session #{safe_prefix(label_of(info, dir), 1_024)} — latest #{latest}\n"
end

# Claude Code resumes a session from the directory it ran in.
fn resume_line(info: SessionInfo) : String
  return "" if info.id == "" or info.id.size > 256
  command = "claude --resume #{shell_word(info.id)}"
  return "  resume: #{command}\n" if info.cwd == "" or info.cwd.size > 1_024
  "  resume: cd #{shell_word(info.cwd)} && #{command}\n"
end

fn render_hit(rendered: Render, hit: Message, dir: String) : Render
  var next = append(rendered,
    "  #{safe_prefix(hit.role, 256)} message #{safe_prefix(hit.id, 256)}\n")
  for block in hit.blocks
    if next.truncated
      break
    end
    api = case block.api_index
      Some(index): " apiBlockIndex=#{index}"
      None: ""
    end
    place = safe_prefix(display(dir, block.path), 1_024)
    next = append(next,
      "    #{place}:#{block.line} #{safe_prefix(block.label, 256)} content[#{block.local_index}]#{api}\n")
    next = append(next, "      #{block.excerpt}\n")
  end
  next
end

# A path as the operator can open it: joined to the directory exactly as it was typed.
fn display(dir: String, path: String) : String
  root = trimmed(dir)
  return path if root == "." or path == ""
  return root if path == "."
  return "/#{path}" if root == "/"
  "#{root}/#{path}"
end

fn trimmed(dir: String) : String
  return dir if dir == "/" or !dir.ends_with?("/")
  trimmed(dir.slice(0, dir.size - 1))
end

fn diagnostics_text(scan: Scan, options: Options, limit: UInt64) : Render
  var next = Render(parts: [], bytes: 0, truncated: false)
  for issue in scan.errors
    next = append_limit(next, "moscope: error: #{located(options.dir, issue)}\n", limit)
  end
  if scan.errors.size >= diagnostics()
    next = append_limit(next, "moscope: error: diagnostic retention limit reached\n", limit)
  end
  for pair in scan.warnings.entries.sort_by(fn(entry) entry.0 end)
    place = safe_prefix(display(options.dir, pair.1.path), 1_024)
    next = append_limit(next,
      "moscope: warning: #{safe_prefix(pair.0, 256)} (#{pair.1.count}; first at #{place}:#{pair.1.line})\n",
      limit)
  end
  if options.strict and scan.warnings.size > 0
    next = append_limit(next, "moscope: error: --strict treats the warnings above as errors\n",
      limit)
  end
  notes_text(next, scan, limit)
end

fn notes_text(rendered: Render, scan: Scan, limit: UInt64) : Render
  var next = rendered
  if scan.skipped_links > 0
    next = append_limit(next,
      "moscope: note: skipped #{counted(scan.skipped_links, "discovered symlink")}\n", limit)
  end
  ignored = scan.ignored.values.reduce(0, fn(sum, n) sum.saturating_add(n) end)
  if ignored > 0
    next = append_limit(next,
      "moscope: note: ignored #{counted(ignored, "non-conversation record")} of #{counted(scan.ignored.size, "kind")}\n",
      limit)
  end
  next
end

fn counted(count: UInt64, noun: String) : String
  if count == 1: "1 #{noun}" else: "#{count} #{noun}s"
end

fn located(dir: String, issue: Issue) : String
  detail = safe_prefix(issue.detail, 512)
  return detail if issue.path == ""
  path = safe_prefix(display(dir, issue.path), 1_024)
  place = if issue.line == 0: path else: "#{path}:#{issue.line}"
  "#{place}: #{detail}"
end

fn append(rendered: Render, addition: String) : Render
  # Keep room for a short error explanation after result truncation.
  append_limit(rendered, addition, output_bytes().saturating_sub(512))
end

fn append_limit(rendered: Render, addition: String, limit: UInt64) : Render
  return rendered if rendered.truncated or addition == ""
  bytes = rendered.bytes.saturating_add(addition.byte_size)
  if bytes > limit
    return Render(parts: rendered.parts, bytes: rendered.bytes, truncated: true)
  end
  Render(parts: rendered.parts.push(addition), bytes: bytes, truncated: false)
end

fn info(id: String, cwd: String) : SessionInfo
  SessionInfo(key: "session:#{id}", path: "a.jsonl", id: id, cwd: cwd, latest: None)
end

test "paths join the directory as typed, without doubled slashes"
  assert display(".", "a.jsonl") == "a.jsonl"
  assert display("sessions/", "a.jsonl") == "sessions/a.jsonl"
  assert display("/", "a.jsonl") == "/a.jsonl"
  assert display("~/x", ".") == "~/x"
  assert display("~/x", "") == ""
end

test "the resume hint changes to the session directory and quotes what needs it"
  assert resume_line(info("abc-1",
    "/work/app")) == "  resume: cd /work/app && claude --resume abc-1\n"
  assert resume_line(info("abc-1",
    "/my work")) == "  resume: cd '/my work' && claude --resume abc-1\n"
  assert resume_line(info("abc-1", "")) == "  resume: claude --resume abc-1\n"
  assert resume_line(info("", "/work")) == ""
end

test "a session without an id is named by its file as the operator can open it"
  assert label_of(info("", ""), "sessions/") == "(missing session id in sessions/a.jsonl)"
  assert label_of(info("abc", ""), "sessions") == "abc"
  assert counted(1, "kind") == "1 kind" and counted(2, "kind") == "2 kinds"
end

test "output admission differs on both sides of the limit"
  base = Render(parts: ["1234"], bytes: 4, truncated: false)
  full = append_limit(base, "5", 4)
  assert full.truncated and full.bytes == 4
  room = append_limit(base, "5", 5)
  assert !room.truncated and String.join(room.parts, "") == "12345"
end

verified: types, contracts, tests (4), property (0 seeds), sim (not run)
          proven: not run
