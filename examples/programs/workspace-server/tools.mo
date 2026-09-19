module WorkspaceServer.Tools
expose Problem, run, parts, inventory, offsets, bounded, ascii_size, controller_cap, file_cap

use WorkspaceServer.Envelope{Outcome, Produced, Row, Hit, done, refusal, timed_out, result_text, row_text, hit_text}
use WorkspaceServer.Schema{Call}

intent "The five file tools over the workspace folder, held as one narrowed Fs, with workspace_files.py's limits and refusals: lexical paths only, a regular file with one link and no setuid bit, at most 64 KiB a file, 1,000 files and 64 MiB a tree, 4,096 entries walked, the whole tree checked before a write, exact_edit's one match, 200 search hits, results bounded to what the controller's 65,280-byte reply holds; every filesystem call waits only until the caller's deadline, so the work never outlives the wait."

# Why a tool call stopped short. The first three are FsError's own, so `try` carries them.
enum Problem
  Missing(path: String)
  Timeout
  NotText
  Code(name: String)
end

fn file_cap() : UInt64
  65_536
end

# The controller refuses a reply of more than 65,536 - 256 bytes of JSON.
fn controller_cap() : UInt64
  65_280
end

# One call's outcome. `command` is not served by this server; its refusal is the caller's.
fn run(fs: Fs, call: Call, by: Deadline) : Outcome
  got = case call.operation
    "list_files": listed(fs, call.args.get("path") or ".", by)
    "read_file": read_file(fs, call.args.get("path") or "", by)
    "search": search(fs, call.args.get("query") or "", call.args.get("path") or ".", by)
    "write_file": write_file(fs, call.args.get("path") or "", call.args.get("text") or "", by)
    "exact_edit": exact_edit(fs, call.args, by)
    _: Error(Code(name: "request_refused"))
  end
  case got
    Ok(produced): within_controller(produced)
    Error(Timeout): timed_out()
    Error(Missing(_)): refusal("filesystem_refusal")
    Error(NotText): refusal("invalid_utf8")
    Error(Code(name)): refusal(name)
  end
end

# A result the controller could not have sent whole is refused whole, as its reply would be.
fn within_controller(produced: Produced) : Outcome
  text = result_text(produced) or ""
  return refusal("result_too_large") if 223 + ascii_size(text) > controller_cap()
  done(produced)
end

# The bytes a JSON text takes with every non-ASCII character escaped, as Python writes it.
fn ascii_size(text: String) : UInt64
  text.byte_size + text.bytes.map(fn(b) escaped_extra(b) end).sum
end

# What escaping adds for the character a byte starts: \uXXXX for two or three UTF-8 bytes, a
# surrogate pair of them for four.
fn escaped_extra(b: UInt8) : UInt64
  if b >= 240
    return 8
  end
  if b >= 224
    return 3
  end
  if b >= 192: 4 else: 0
end

# A path's components: relative, no empty, `.` or `..` component, none past 255 bytes, no NUL,
# at most 4,096 bytes. `.` is the root where a root may be named.
fn parts(path: String, root: Bool) : Result(List(String), Problem)
  return Ok([]) if root and path == "."
  if path == "" or path.contains?("\u{0}") or path.byte_size > 4_096
    return Error(Code(name: "invalid_path"))
  end
  pieces = path.split("/")
  if pieces.any?(fn(p) p == "" or p == "." or p == ".." or p.byte_size > 255 end)
    return Error(Code(name: "invalid_path"))
  end
  Ok(pieces)
end

# The size of a regular file of one link and no setuid bit, within the file cap.
fn regular(fs: Fs, path: String, by: Deadline) : Result(UInt64, Problem)
  entry = try fs.kind_of(path, within: by)
  case entry.kind
    File:
      return Error(Code(name: "unsupported_entry")) if entry.links != 1
      return Error(Code(name: "unsupported_mode")) if entry.setuid
      size = try fs.size(path, within: by)
      return Error(Code(name: "oversized")) if size > file_cap()
      Ok(size)
    Folder: Error(Code(name: "unsupported_entry"))
    Link: Error(Missing(path: path))
  end
end

fn text_of(fs: Fs, path: String, by: Deadline) : Result(String, Problem)
  try parts(path, false)
  try regular(fs, path, by)
  text = try fs.read(path, within: by)
  Ok(text)
end

# Every file under the root, sorted by path, with its length and SHA-256; a link, a special
# entry or a setuid bit anywhere refuses the whole walk.
fn inventory(fs: Fs, root: String, by: Deadline) : Result(List(Row), Problem)
  start = try parts(root, true)
  var folders = [String.join(start, "/")]
  var rows = [Row(path: "", length: 0, sha256: "")].take(0)
  var entries = 0
  var total = 0
  for _ in 0..4_097
    if folders.size == 0
      break
    end
    folder = folders.first or ""
    folders = folders.drop(1)
    listing = try (if folder == "": fs else: fs.scoped(folder)).list_kinds(within: by)
    entries += listing.size
    return Error(Code(name: "too_many_entries")) if entries > 4_096
    for entry in listing.sort_by(fn(e) e.name end)
      path = if folder == "": entry.name else: "#{folder}/#{entry.name}"
      try parts(path, false)
      return Error(Missing(path: path)) if entry.kind == Link
      return Error(Code(name: "unsupported_mode")) if entry.setuid
      if entry.kind == Folder
        folders = folders.push(path)
      else
        row = try row_of(fs, path, by)
        total += row.length
        return Error(Code(name: "quota")) if rows.size >= 1_000 or total > 67_108_864
        rows = rows.push(row)
      end
    end
  end
  Ok(rows.sort_by(fn(r) r.path end))
end

fn row_of(fs: Fs, path: String, by: Deadline) : Result(Row, Problem)
  try regular(fs, path, by)
  bytes = try fs.read_bytes(path, within: by)
  return Error(Code(name: "oversized")) if bytes.size > file_cap()
  Ok(Row(path: path, length: bytes.size, sha256: Hash.hex(Hash.sha256(bytes))))
end

# How many of these items fit a result of at most `limit` items and 64,512 bytes of JSON, and
# whether any were left out.
fn bounded(texts: List(String), limit: UInt64) : (UInt64, Bool)
  var size = 33
  var n = 0
  for text in texts
    grown = size + ascii_size(text) + (if n > 0: 2 else: 0)
    if n + 1 > limit or grown > 64_512
      return (n, true)
    end
    size = grown
    n += 1
  end
  (n, false)
end

fn listed(fs: Fs, root: String, by: Deadline) : Result(Produced, Problem)
  rows = try inventory(fs, root, by)
  fit = bounded(rows.map(fn(r) row_text(r) end), 1_000)
  Ok(Listed(rows: rows.take(fit.0), truncated: fit.1))
end

fn read_file(fs: Fs, path: String, by: Deadline) : Result(Produced, Problem)
  text = try text_of(fs, path, by)
  Ok(Read(text: text))
end

# The byte offsets where `needle` starts in `text`, overlapping ones included, at most `room`.
fn offsets(text: String, needle: String, room: UInt64) : List(UInt64)
  var found = [0].take(0)
  var from = 0
  for _ in 0..room
    at = text.slice(from, text.size).index_of(needle) or text.size
    if at == text.size
      break
    end
    found = found.push(text.slice(0, from + at).byte_size)
    from = from + at + 1
  end
  found
end

fn search(fs: Fs, query: String, root: String, by: Deadline) : Result(Produced, Problem)
  return Error(Code(name: "oversized")) if query.byte_size > file_cap()
  return Error(Code(name: "empty_search")) if query == ""
  rows = try inventory(fs, root, by)
  var hits = [Hit(path: "", offset: 0)].take(0)
  for row in rows
    text = try text_of(fs, row.path, by)
    if hits.size <= 200
      hits = hits.concat(offsets(text, query, 201 - hits.size).map(fn(o) Hit(path: row.path, offset: o) end))
    end
  end
  fit = bounded(hits.map(fn(h) hit_text(h) end), 200)
  Ok(Found(hits: hits.take(fit.0), truncated: fit.1))
end

# The whole tree is checked first, as the controller checks it before any write.
fn write_file(fs: Fs, path: String, text: String, by: Deadline) : Result(Produced, Problem)
  rows = try inventory(fs, ".", by)
  return Error(Code(name: "oversized")) if text.byte_size > file_cap()
  existing = rows.find(fn(r) r.path == path end)
  return Error(Code(name: "quota")) if existing == None and rows.size >= 1_000
  total = rows.map(fn(r) r.length end).sum - (existing.map(fn(r) r.length end) or 0)
  return Error(Code(name: "quota")) if total + text.byte_size > 67_108_864
  pieces = try parts(path, false)
  try folder_there(fs, pieces.take(pieces.size - 1), by)
  if existing == None and fs.kind_of(path, within: by) is Ok(entry)
    return Error(Code(name: if entry.kind == Link: "filesystem_refusal" else: "unsupported_entry"))
  end
  try fs.replace(path, text, within: by)
  Ok(Written)
end

# The folder a new file goes in must be there already: a write makes no folders.
fn folder_there(fs: Fs, folder: List(String), by: Deadline) : Result(Bool, Problem)
  return Ok(true) if folder.size == 0
  path = String.join(folder, "/")
  entry = try fs.kind_of(path, within: by)
  return Error(Missing(path: path)) if entry.kind != Folder
  Ok(true)
end

fn exact_edit(fs: Fs, args: Map(String, String), by: Deadline) : Result(Produced, Problem)
  path = args.get("path") or ""
  old = args.get("old_text") or ""
  new = args.get("new_text") or ""
  try inventory(fs, ".", by)
  before = try text_of(fs, path, by)
  return Error(Code(name: "oversized")) if old.byte_size > file_cap() or new.byte_size > file_cap()
  return Error(Code(name: "empty_old")) if old == ""
  found = offsets(before, old, 2)
  return Error(Code(name: "multiple_matches")) if found.size > 1
  at = before.index_of(old) or before.size
  return Error(Code(name: "missing_match")) if at == before.size
  after = "#{before.slice(0, at)}#{new}#{before.slice(at + old.size, before.size)}"
  return Error(Code(name: "oversized")) if after.byte_size > file_cap()
  try fs.replace(path, after, within: by)
  Ok(Edited)
end

fn a_call(operation: String, args: Map(String, String)) : Call
  Call(run_id: "r", workspace_id: "0".repeat(32), call_id: "c", operation: operation, args: args,
    timeout_ms: 0)
end

fn made(fs: Fs, files: List((String, String))) : Bool
  for f in files
    if fs.write(f.0, f.1, within: 1.minute) is Error(_)
      return false
    end
  end
  true
end

test "paths are lexical: escapes and odd components are invalid_path"
  bad = ["../escape", "/etc/passwd", "a//b", "a/./b", "answer/..", "", "a\u{0}b", "x".repeat(256)]
  assert bad.all?(fn(p) parts(p, false) == Error(Code(name: "invalid_path")) end)
  assert parts(".", true) == Ok([])
  assert parts("a/b", false) == Ok(["a", "b"])
end

test "the five tools on a small tree"
  fs = Fs.fixture()
  by = Deadline.fixture(1.minute)
  assert made(fs, [("a", "héllo"), ("scenario", "")])
  listed = run(fs, a_call("list_files", Map.new()), by)
  assert listed.produced is Listed(rows: rows, truncated: false)
  assert rows.map(fn(r) r.path end) == ["a", "scenario"]
  assert run(fs, a_call("read_file", Map.new().set("path", "a")), by) == done(Read(text: "héllo"))
  found = run(fs, a_call("search", Map.new().set("query", "é")), by)
  assert found == done(Found(hits: [Hit(path: "a", offset: 1)], truncated: false))
  wrote = run(fs, a_call("write_file", Map.new().set("path", "a").set("text", "b")), by)
  assert wrote == done(Written)
  edit = Map.new().set("path", "a").set("old_text", "b").set("new_text", "c")
  assert run(fs, a_call("exact_edit", edit), by) == done(Edited)
  assert fs.read("a", within: 1.minute) == Ok("c")
end

test "exact_edit changes nothing unless exactly one non-empty match"
  fs = Fs.fixture()
  by = Deadline.fixture(1.minute)
  assert made(fs, [("answer", "aaa\n")])
  for pair in [("zzz", "missing_match"), ("a", "multiple_matches"), ("", "empty_old"), ("aa", "multiple_matches")]
    edit = Map.new().set("path", "answer").set("old_text", pair.0).set("new_text", "b")
    assert run(fs, a_call("exact_edit", edit), by) == refusal(pair.1)
  end
  assert fs.read("answer", within: 1.minute) == Ok("aaa\n")
end

test "a file past 64 KiB is oversized, even for a write elsewhere in its tree, and a reply past the controller's cap is refused whole"
  fs = Fs.fixture()
  by = Deadline.fixture(1.minute)
  assert made(fs, [("large", "x".repeat(65_536)), ("huge", "x".repeat(65_537))])
  assert run(fs, a_call("read_file", Map.new().set("path", "large")), by) == refusal("result_too_large")
  assert run(fs, a_call("read_file", Map.new().set("path", "huge")), by) == refusal("oversized")
  assert run(fs, a_call("read_file", Map.new().set("path", "gone")), by) == refusal("filesystem_refusal")
  write = Map.new().set("path", "a").set("text", "x")
  assert run(fs, a_call("write_file", write), by) == refusal("oversized")
  clean = Fs.fixture()
  assert made(clean, [("a", "")])
  missing = Map.new().set("path", "no/such/dir").set("text", "x")
  assert run(clean, a_call("write_file", missing), by) == refusal("filesystem_refusal")
end

test "search stops at 200 hits and says so; a listing is cut by its bytes"
  fs = Fs.fixture()
  by = Deadline.fixture(1.minute)
  assert made(fs, [("h/hits", "x".repeat(1_000))])
  found = run(fs, a_call("search", Map.new().set("query", "x").set("path", "h")), by)
  assert found.produced is Found(hits: hits, truncated: true)
  assert hits.size == 200
  assert offsets("aaa", "aa", 10) == [0, 1]
  assert offsets("héllo", "l", 10) == [3, 4]
  assert bounded(["x".repeat(40_000), "y".repeat(40_000)], 10) == (1, true)
  assert ascii_size("é🌊") == 18
end

test "a call past its deadline is a timeout of unknown execution"
  slow = Fs.fixture(delay: 1.minute)
  got = run(slow, a_call("read_file", Map.new().set("path", "a")), Deadline.fixture(10.ms))
  assert got == timed_out()
end
